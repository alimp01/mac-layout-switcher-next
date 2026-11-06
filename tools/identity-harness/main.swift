import AppKit
import Foundation

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let config = Config()
precondition(config.directory.lastPathComponent == "MacLayoutSwitcherNext")
let model = SpeechModelStore()
precondition(model.modelDirectory.deletingLastPathComponent().deletingLastPathComponent() == config.directory)
precondition(model.modelDirectory.lastPathComponent == "gigaam-v3-e2e-2026-06-22")

let stable = CaptureSessionGuard.Application(pid: 42, bundleID: "space.alimp.maclayoutswitcher", executableName: "Renamed")
let unbundled = CaptureSessionGuard.Application(pid: 43, bundleID: nil, executableName: "MacLayoutSwitcher")
let unrelated = CaptureSessionGuard.Application(pid: 44, bundleID: "com.apple.TextEdit", executableName: "TextEdit")
func refused(_ expected: CaptureSessionGuard.Refusal, _ action: () throws -> Void) {
    do { try action(); fatalError("Expected refusal: \(expected)") }
    catch { precondition(error.localizedDescription == expected.localizedDescription, "Unexpected error: \(error)") }
}
for peer in [stable, unbundled] {
    let guarder = CaptureSessionGuard(directory: directory.appendingPathComponent("not-created"), applications: { [peer] })
    refused(.stableRunning) { try guarder.acquire() }
}
precondition(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("not-created").path))
let center = NotificationCenter()
var peers = [unrelated]
var first: CaptureSessionGuard? = CaptureSessionGuard(directory: directory, applications: { peers }, notifications: center)
try first!.acquire()
try first!.checkBeforeCapture()
let second = CaptureSessionGuard(directory: directory, applications: { [] })
refused(.nextRunning) { try second.acquire() }
var conflicts = 0
first!.onConflict = { refusal in precondition(refusal == .stableRunning); conflicts += 1 }
first!.watchForConflicts()
peers = [stable]
refused(.stableRunning) { try first!.checkBeforeCapture() }
center.post(name: NSWorkspace.willLaunchApplicationNotification, object: nil)
center.post(name: NSWorkspace.didLaunchApplicationNotification, object: nil)
precondition(conflicts == 1, "stop once on public launch notification")
peers = []
refused(.lockUnavailable) { try first!.checkBeforeCapture() }
first = nil
try second.acquire()
try second.checkBeforeCapture()
let blocked = directory.appendingPathComponent("blocked")
try Data().write(to: blocked)
let unavailable = CaptureSessionGuard(directory: blocked, applications: { [] })
refused(.lockUnavailable) { try unavailable.acquire() }
print("Next identity/session PASS: default paths, stable/unbundled refusal, exclusive lock, resume, launch notification, release, fail-closed I/O")
