#if os(macOS)
import Foundation
import CryptoKit
import Darwin

/// Cancellation is thread-safe. Services always deliver one completion on main;
/// callers must also use their session ID to ignore an obsolete completion.
final class SpeechTask {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func checkCancellation() throws { if isCancelled { throw SpeechError.cancelled } }
}

enum SpeechError: LocalizedError {
    case cancelled, busy, missingModel, damagedModel, download, unsupported
    case missingHelper, invalidAudio, engine, noSpeech, timeout, outputLimit
    var errorDescription: String? {
        switch self {
        case .cancelled: return "Диктовка отменена."
        case .busy: return "Предыдущая операция диктовки ещё завершается."
        case .missingModel: return "Модель диктовки ещё не установлена."
        case .damagedModel: return "Модель неполная или повреждена. Повторите подготовку диктовки."
        case .download: return "Не удалось загрузить модель. Проверьте интернет и повторите."
        case .unsupported: return "Диктовка требует Apple Silicon и macOS 13.4 или новее."
        case .missingHelper: return "Движок диктовки отсутствует. Пересоберите или обновите приложение."
        case .invalidAudio: return "Не удалось прочитать запись. Попробуйте ещё раз."
        case .engine: return "Ошибка локального распознавания. Попробуйте ещё раз."
        case .noSpeech: return "Речь не обнаружена. Попробуйте говорить ближе к микрофону."
        case .timeout: return "Распознавание заняло слишком много времени. Попробуйте запись короче."
        case .outputLimit: return "Движок вернул слишком большой ответ. Попробуйте запись короче."
        }
    }
}

/// No I/O or network at init. All disk work is on a serial worker; callbacks on main.
final class SpeechModelStore {
    struct Artifact {
        let name: String
        let bytes: Int64
        let sha256: String
    }
    static let artifacts: [Artifact] = [
        .init(name: "v3_e2e_rnnt_encoder_int8.onnx", bytes: 225250603, sha256: "cf51b300af47cea099e17c806f8fecce2c46e9e8deb4709ec203f8970a067389"),
        .init(name: "v3_e2e_rnnt_decoder.onnx", bytes: 4599910, sha256: "7b0a16d67fd2cb37061decc93c69e364a9ab27afee3c57495d55b1c974cf7231"),
        .init(name: "v3_e2e_rnnt_joint.onnx", bytes: 2712896, sha256: "602ff7017a93311aad34df1437c8d7f49911353c13d6eae7a6ee7b041339465c"),
        .init(name: "v3_e2e_rnnt_vocab.txt", bytes: 13354, sha256: "39abae20e692998290c574e606f11a9edef2902a1995463fcff63d1490cf22b7")
    ]
    static let totalDownloadBytes = artifacts.reduce(Int64(0)) { $0 + $1.bytes }
    private static let baseURL = URL(string: "https://github.com/ekhodzitsky/gigastt/releases/download/models-v3-2026-06-22/")!
    let modelDirectory: URL
    private let rootURL: URL
    private let queue = DispatchQueue(label: "space.alimp.speech.models", qos: .utility)
    private let lock = NSLock()
    private var active: SpeechTask?

    init(rootURL: URL? = nil) {
        self.rootURL = rootURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacLayoutSwitcherNext/SpeechModels", isDirectory: true)
        modelDirectory = self.rootURL.appendingPathComponent("gigaam-v3-e2e-2026-06-22", isDirectory: true)
    }
    func cancel() { lock.lock(); let task = active; lock.unlock(); task?.cancel() }

    /// App termination waits for cancellation and owned temporary-file cleanup.
    /// Do not start another operation after requesting shutdown.
    func shutdown(completion: @escaping () -> Void) {
        cancel()
        queue.async { DispatchQueue.main.async(execute: completion) }
    }


    @discardableResult
    func checkInstalled(completion: @escaping (Result<URL, Error>) -> Void) -> SpeechTask {
        perform(completion: completion) { task in
            guard FileManager.default.fileExists(atPath: self.modelDirectory.path) else { throw SpeechError.missingModel }
            try self.validate(directory: self.modelDirectory, task: task)
            return self.modelDirectory
        }
    }

    @discardableResult
    func download(progress: @escaping (Double) -> Void,
                  completion: @escaping (Result<URL, Error>) -> Void) -> SpeechTask {
        perform(completion: completion) { task in
            let fm = FileManager.default
            try fm.createDirectory(at: self.rootURL, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            let staging = self.rootURL.appendingPathComponent(".download-\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: staging, withIntermediateDirectories: false,
                                   attributes: [.posixPermissions: 0o700])
            defer { try? fm.removeItem(at: staging) }
            var completed: Int64 = 0
            for artifact in Self.artifacts {
                try task.checkCancellation()
                let previous = completed
                let download = ModelDownload(destination: staging.appendingPathComponent(artifact.name),
                                             expectedBytes: artifact.bytes) { bytes in
                    let fraction = min(0.999, Double(previous + bytes) / Double(Self.totalDownloadBytes))
                    DispatchQueue.main.async { if !task.isCancelled { progress(fraction) } }
                }
                try download.run(url: Self.baseURL.appendingPathComponent(artifact.name), cancellation: task)
                try Self.validate(file: staging.appendingPathComponent(artifact.name), artifact: artifact, task: task)
                completed += artifact.bytes
            }
            try task.checkCancellation()
            // Atomic directory publication on the same filesystem. With an old
            // model, swap names atomically; defer removes the old directory.
            if fm.fileExists(atPath: self.modelDirectory.path) {
                guard renameatx_np(AT_FDCWD, staging.path, AT_FDCWD, self.modelDirectory.path, UInt32(RENAME_SWAP)) == 0 else {
                    throw CocoaError(.fileWriteUnknown)
                }
            } else { try fm.moveItem(at: staging, to: self.modelDirectory) }
            DispatchQueue.main.async { if !task.isCancelled { progress(1) } }
            return self.modelDirectory
        }
    }

    private func perform(completion: @escaping (Result<URL, Error>) -> Void,
                         operation: @escaping (SpeechTask) throws -> URL) -> SpeechTask {
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
            let result = Result { try task.checkCancellation(); return try operation(task) }
            self.lock.lock(); self.active = nil; self.lock.unlock()
            DispatchQueue.main.async {
                completion(task.isCancelled ? .failure(SpeechError.cancelled) : result)
            }
        }
        return task
    }

    private func validate(directory: URL, task: SpeechTask) throws {
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw SpeechError.damagedModel }
        // The pinned CPU helper creates this one derived encoder cache. Keep
        // rejecting other encoders/manifests that could change model selection.
        let names = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
        let required = Set(Self.artifacts.map(\.name))
        guard names == required || names == required.union(["optimized_cache"]) else {
            throw SpeechError.damagedModel
        }
        if names.contains("optimized_cache") {
            let cache = directory.appendingPathComponent("optimized_cache", isDirectory: true)
            let values = try cache.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { throw SpeechError.damagedModel }
            let entries = try FileManager.default.contentsOfDirectory(atPath: cache.path)
            for name in entries {
                guard name == "v3_e2e_rnnt_encoder_int8_optimized.ort" else { throw SpeechError.damagedModel }
                let file = try cache.appendingPathComponent(name).resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard file.isRegularFile == true, file.isSymbolicLink != true else { throw SpeechError.damagedModel }
            }
        }
        for artifact in Self.artifacts {
            try Self.validate(file: directory.appendingPathComponent(artifact.name), artifact: artifact, task: task)
        }
    }
    private static func validate(file: URL, artifact: Artifact, task: SpeechTask) throws {
        try task.checkCancellation()
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              Int64(values.fileSize ?? -1) == artifact.bytes else { throw SpeechError.damagedModel }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            try task.checkCancellation()
            hash.update(data: data)
        }
        guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == artifact.sha256 else {
            throw SpeechError.damagedModel
        }
    }
}

/// URLSession streams to disk, with bounded size, timeout, cancellation and no
/// persistent URL cache. The delegate queue is serial; semaphore publishes result.
private final class ModelDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let destination: URL
    let expectedBytes: Int64
    let progress: (Int64) -> Void
    private let finished = DispatchSemaphore(value: 0)
    private var failure: Error?
    private var receivedFile = false
    init(destination: URL, expectedBytes: Int64, progress: @escaping (Int64) -> Void) {
        self.destination = destination; self.expectedBytes = expectedBytes; self.progress = progress
    }
    func run(url: URL, cancellation: SpeechTask) throws {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 3600
        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: config, delegate: self, delegateQueue: delegateQueue)
        defer { session.invalidateAndCancel() }
        let task = session.downloadTask(with: url)
        task.resume()
        while finished.wait(timeout: .now() + 0.1) == .timedOut {
            if cancellation.isCancelled { task.cancel() }
        }
        try cancellation.checkCancellation()
        if let failure { throw failure }
        guard receivedFile else { throw SpeechError.download }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > expectedBytes {
            failure = SpeechError.damagedModel; downloadTask.cancel()
        } else { progress(totalBytesWritten) }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let response = downloadTask.response as? HTTPURLResponse, response.statusCode == 200 else {
            failure = SpeechError.download; return
        }
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            receivedFile = true
        } catch { failure = error }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if failure == nil { failure = error }
        finished.signal()
    }
}
#endif
