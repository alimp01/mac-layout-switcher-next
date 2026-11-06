#if os(macOS)
import AVFoundation
import Foundation

/// Every AVFoundation operation and audio file operation runs off the tap/main
/// queue. The serial queue orders a cancelled startup before its cleanup.
final class DictationRecorder: NSObject, AVAudioRecorderDelegate {
    private let queue = DispatchQueue(label: "MacLayoutSwitcher.Microphone", qos: .userInitiated)
    private var recorder: AVAudioRecorder?
    private var directory: URL?
    private var token: UInt64?
    var onUnexpectedStop: ((UInt64, Bool) -> Void)?

    func start(token: UInt64, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [self] in
            cleanup()
            do {
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MacLayoutSwitcherNext-recording-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                       attributes: [.posixPermissions: 0o700])
                directory = folder
                let audio = try AVAudioRecorder(url: folder.appendingPathComponent("speech.wav"), settings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: 16_000.0,
                    AVNumberOfChannelsKey: 1,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                ])
                audio.delegate = self
                guard audio.prepareToRecord(), audio.record(forDuration: 300) else {
                    throw NSError(domain: "Dictation", code: 1, userInfo: [NSLocalizedDescriptionKey: "Не удалось включить микрофон. Проверьте устройство ввода в настройках звука."])
                }
                recorder = audio
                self.token = token
                DispatchQueue.main.async { completion(.success(())) }
            } catch {
                cleanup()
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    func stop(completion: @escaping (URL?) -> Void) {
        queue.async { [self] in
            let url = recorder?.url
            recorder?.delegate = nil
            recorder?.stop()
            recorder = nil
            token = nil
            DispatchQueue.main.async { completion(url) }
        }
    }

    func cancel() { queue.async { [self] in cleanup() } }

    func shutdown(completion: @escaping () -> Void) {
        queue.async { [self] in
            cleanup()
            DispatchQueue.main.async(execute: completion)
        }
    }

    private func cleanup() {
        recorder?.delegate = nil
        recorder?.stop()
        recorder = nil
        token = nil
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        queue.async { [weak self] in
            guard let self, self.recorder === recorder, let token = self.token else { return }
            DispatchQueue.main.async { self.onUnexpectedStop?(token, flag) }
        }
    }
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        audioRecorderDidFinishRecording(recorder, successfully: false)
    }
}
#endif
