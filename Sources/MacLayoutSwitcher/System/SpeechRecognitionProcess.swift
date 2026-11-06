#if os(macOS)
import Foundation
import Darwin

/// Owns only its private copy of the WAV. Caller keeps ownership of wavURL and
/// must retain it until completion, then remove the original recording itself.
/// Every completion is delivered once on main, including cancellation/errors.
final class SpeechRecognitionProcess {
    static var unavailabilityReason: String? {
        #if arch(arm64)
        if #available(macOS 13.4, *) { return nil }
        #endif
        return SpeechError.unsupported.localizedDescription
    }
    private let helperURL: URL
    private let queue = DispatchQueue(label: "space.alimp.speech.process", qos: .userInitiated)
    private let lock = NSLock()
    private var active: SpeechTask?
    init(helperURL: URL? = nil) {
        self.helperURL = helperURL ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/SpeechRecognizer")
    }
    func cancel() { lock.lock(); let task = active; lock.unlock(); task?.cancel() }

    /// App termination waits for cancellation and owned temporary-file cleanup.
    /// Do not start another operation after requesting shutdown.
    func shutdown(completion: @escaping () -> Void) {
        cancel()
        queue.async { DispatchQueue.main.async(execute: completion) }
    }


    @discardableResult
    func transcribe(wavURL: URL, modelDirectory: URL, timeout: TimeInterval = 180,
                    completion: @escaping (Result<String, Error>) -> Void) -> SpeechTask {
        let task = SpeechTask()
        lock.lock()
        guard active == nil else {
            lock.unlock()
            DispatchQueue.main.async { completion(.failure(SpeechError.busy)) }
            return task
        }
        active = task
        lock.unlock()
        queue.async {
            let result = Result { try self.run(wavURL: wavURL, modelDirectory: modelDirectory,
                                              timeout: timeout, task: task) }
            self.lock.lock(); self.active = nil; self.lock.unlock()
            DispatchQueue.main.async {
                completion(task.isCancelled ? .failure(SpeechError.cancelled) : result)
            }
        }
        return task
    }

    private struct Response: Decodable { let text: String?; let error: String? }
    private func run(wavURL: URL, modelDirectory: URL, timeout: TimeInterval, task: SpeechTask) throws -> String {
        try task.checkCancellation()
        guard Self.unavailabilityReason == nil else { throw SpeechError.unsupported }
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: helperURL.path) else { throw SpeechError.missingHelper }
        guard timeout.isFinite, timeout > 0 else { throw SpeechError.timeout }
        let source = try wavURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard source.isRegularFile == true, let size = source.fileSize, size > 0,
              size <= 128 * 1024 * 1024 else { throw SpeechError.invalidAudio }
        let directory = fm.temporaryDirectory.appendingPathComponent("MacLayoutSwitcherNext-speech-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: directory) }
        let audio = directory.appendingPathComponent("recording.wav")
        try fm.copyItem(at: wavURL, to: audio)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: audio.path)
        try task.checkCancellation()

        let process = Process()
        let output = Pipe(), diagnostics = Pipe()
        process.executableURL = helperURL
        process.currentDirectoryURL = directory
        process.arguments = [modelDirectory.standardizedFileURL.path, audio.lastPathComponent]
        // Do not inherit model/ORT/debug overrides from a launching shell.
        process.environment = ["PATH": "/usr/bin:/bin", "TMPDIR": directory.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = diagnostics
        defer {
            try? output.fileHandleForReading.close()
            try? output.fileHandleForWriting.close()
            try? diagnostics.fileHandleForReading.close()
            try? diagnostics.fileHandleForWriting.close()
        }
        try process.run()
        // Close our writer ends, and drain both pipes using nonblocking reads.
        // No readability-handler race, unbounded readToEnd, or pipe deadlock.
        try? output.fileHandleForWriting.close()
        try? diagnostics.fileHandleForWriting.close()
        let outFD = output.fileHandleForReading.fileDescriptor
        let errFD = diagnostics.fileHandleForReading.fileDescriptor
        _ = fcntl(outFD, F_SETFL, O_NONBLOCK)
        _ = fcntl(errFD, F_SETFL, O_NONBLOCK)
        var stdout = Data()
        var stderrBytes = 0
        var failure: SpeechError?
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var killAt: TimeInterval?
        func drain(_ fd: Int32, keep: Bool) {
            var bytes = [UInt8](repeating: 0, count: 4096)
            // Bound work per iteration too: a noisy child cannot starve cancel.
            for _ in 0..<32 {
                let count = Darwin.read(fd, &bytes, bytes.count)
                if count <= 0 { return }
                if keep {
                    if stdout.count + count <= 65536 { stdout.append(contentsOf: bytes.prefix(count)) }
                    else { failure = failure ?? .outputLimit }
                } else {
                    stderrBytes += count
                    if stderrBytes > 32768 { failure = failure ?? .outputLimit }
                    // Diagnostics are deliberately discarded, never logged.
                }
            }
        }
        repeat {
            drain(outFD, keep: true)
            drain(errFD, keep: false)
            let now = ProcessInfo.processInfo.systemUptime
            if task.isCancelled { failure = .cancelled }
            else if now >= deadline { failure = failure ?? .timeout }
            if failure != nil && process.isRunning {
                if killAt == nil {
                    process.terminate()
                    killAt = now + 0.5
                } else if now >= killAt! {
                    // Child is still owned and unreaped; do not kill a reused PID.
                    _ = Darwin.kill(process.processIdentifier, SIGKILL)
                }
            }
            if process.isRunning { Thread.sleep(forTimeInterval: 0.02) }
        } while process.isRunning
        process.waitUntilExit()
        drain(outFD, keep: true)
        drain(errFD, keep: false)
        try task.checkCancellation()
        if let failure { throw failure }
        guard let response = try? JSONDecoder().decode(Response.self, from: stdout) else { throw SpeechError.engine }
        if process.terminationStatus != 0 || response.error != nil {
            switch response.error {
            case "no_speech": throw SpeechError.noSpeech
            case "model_load_failed": throw SpeechError.damagedModel
            case "invalid_audio": throw SpeechError.invalidAudio
            default: throw SpeechError.engine
            }
        }
        let text = (response.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw SpeechError.noSpeech }
        return text
    }
}
#endif
