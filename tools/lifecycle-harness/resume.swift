import AppKit
import SwitcherCore

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
func pump(_ seconds: Double) { RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds)) }
func check(_ condition: @autoclosure () -> Bool, _ description: String) {
    if !condition() { print("FAIL: \(description)"); exit(1) }
    print("PASS: \(description)")
}
if !CommandLine.arguments.contains("--engine") {
let delegate = AppDelegate()
delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
precondition(harnessMenus.count == 1 && harnessActiveTaps.count == 1)
let pause = harnessMenus[0].items.first { $0.title == "Пауза" }!
func togglePause() { _ = NSApp.sendAction(pause.action!, to: pause.target, from: pause) }
togglePause()
check(pause.title == "Работа (снять паузу)" && harnessActiveTaps.isEmpty, "pause removes tap and offers resume")
harnessAllowTap = false
togglePause()
check(pause.title == "Работа (снять паузу)", "rejected event tap keeps paused menu")
check(harnessActiveTaps.isEmpty, "rejected resume has no active event tap")
check(harnessAlerts.count == 1, "rejected resume explains recovery")
pump(0.4)
let before = harnessFocusReads()
pump(0.4)
check(harnessFocusReads() == before, "rejected resume stops background focus sampling")
harnessAllowTap = true
togglePause()
check(pause.title == "Пауза" && harnessActiveTaps.count == 1, "later successful resume restores active menu and tap")
togglePause()
}
let config = Config(directory: harnessConfigDirectory.appendingPathComponent("separate-engine"))
let engine = Engine(config: config)
harnessAllowTap = false
check(!engine.start(), "engine reports startup failure")
check(engine.dictation.paused, "failed startup cannot activate dictation")
pump(0.4)
let failedReads = harnessFocusReads()
pump(0.4)
check(harnessFocusReads() == failedReads, "failed initial startup leaves no focus sampler")
engine.stop()
print("PASS: owned app lifecycle; no shown UI, real event tap, microphone or user config")
