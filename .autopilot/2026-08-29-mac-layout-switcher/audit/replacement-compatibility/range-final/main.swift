import AppKit
import ApplicationServices
import SwitcherCore

// Keep SystemDictationAccessibility.focusedElement, Target.capture and the
// complete replacement path. Only raw operating-system RPCs are intercepted:
// fault responses cannot touch another process, and text uses own NSTextView.
enum EventTap { static let syntheticMarker: Int64 = 0xC0FFEE }
var failures = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() { print("PASS: \(message)") }
    else { failures += 1; fputs("FAIL: \(message)\n", stderr) }
}
func main<T>(_ body: () -> T) -> T { Thread.isMainThread ? body() : DispatchQueue.main.sync(execute: body) }
func pump() { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
final class FocusFixture {
    var processID = getpid()
    var ownerPID = getpid()
    let spotlightPID = getpid() + 20
    var spotlightBundleID = "com.apple.Spotlight"
    var spotlightBundleURL = URL(fileURLWithPath: "/System/Library/CoreServices/Spotlight.app")
    var spotlightExecutableURL = URL(fileURLWithPath: "/System/Library/CoreServices/Spotlight.app/Contents/MacOS/Spotlight")
    var spotlightStartSeconds: UInt64 = 1_792_904_729
    var spotlightStartMicroseconds: UInt64 = 518_098
    var spotlightProcResult: Int32? = nil
    var spotlightProcPID: UInt32? = nil
    var spotlightTerminated = false
    var spotlightMissing = false
    var spotlightFrontmost: CFTypeRef? = kCFBooleanFalse
    var spotlightAppFocus: CFTypeRef? = nil
    var postedPIDs: [pid_t] = []
    var observerPIDs: [pid_t] = []
    var spotlightBootstrapCount = 0
    var directSettable = true
    var rangeSettable = true
    var valueSettable = true
    var role: String?
    var enabled: Bool?
    var selectionWrites = 0
    let background = AXUIElementCreateApplication(1_000_004)
    var backgroundReads = 0
    var afterRangeRead: (() -> Void)?
    var app: AXUIElement { AXUIElementCreateApplication(processID) }
    let system = AXUIElementCreateSystemWide()
    // These are opaque identity tokens only. No real RPC uses their fake PIDs.
    let field = AXUIElementCreateApplication(1_000_001)
    let foreign = AXUIElementCreateApplication(1_000_002)
    let other = AXUIElementCreateApplication(1_000_003)
    let editor = NSTextView()
    var frontmostError = AXError.success
    var frontmost: CFTypeRef? = kCFBooleanTrue
    var systemError = AXError.success
    var systemFocus: CFTypeRef?
    var appError = AXError.success
    var appFocus: CFTypeRef?
    var ownerError = AXError.success
    var lazyTree = false
    var rangeNeedsTree = false
    var systemReads = 0
    var bootstrapOnMain = false
    var secureField = false
    var framework: String?
    var launchDate = Date()
    var missingLaunchDate = false
    var manualError = AXError.success
    var enhancedError = AXError.success
    var enhancedReadback: CFTypeRef? = kCFBooleanTrue
    var enhancedDelay: TimeInterval = 2.05
    var enhancedReadyAt: TimeInterval?
    var enhancedCount = 0
    var bootstrapCount = 0
    var writes = 0
    var directWrites = 0
    var directWriteIsNoOp = false
    var trusted = true
    var afterSelection: (() -> Void)?
    var afterMetadataRead: (() -> Void)?
    var afterManual: (() -> Void)?
    init() {
        systemFocus = field; appFocus = field
        editor.string = "before ghbdtn after"
        editor.setSelectedRange(NSRange(location: 13, length: 0))
    }
}
var fixture: FocusFixture!
var fixtureSecureInput = false
struct FixtureRunningApplication {
    let bundleURL: URL?
    let launchDate: Date?
    var bundleIdentifier: String? = nil
    var executableURL: URL? = nil
    var isTerminated = false
}
let metadataRoot = FileManager.default.temporaryDirectory.appendingPathComponent("mls-focus-bundles-" + UUID().uuidString)
func fixtureBundle(framework: String) -> URL {
    // The .app name is deliberately unrelated to the framework identity.
    let bundle = metadataRoot.appendingPathComponent(framework).appendingPathComponent("Renamed.app")
    try! FileManager.default.createDirectory(at: bundle.appendingPathComponent("Contents/Frameworks/" + framework), withIntermediateDirectories: true)
    return bundle
}
defer { try? FileManager.default.removeItem(at: metadataRoot) }
var otherRunningInstances: [pid_t: Date] = [:]
func fixtureRunningApplication(processIdentifier: pid_t) -> FixtureRunningApplication? {
    if let launchDate = otherRunningInstances[processIdentifier] {
        return FixtureRunningApplication(bundleURL: fixtureBundle(framework: "Codex Framework.framework"), launchDate: launchDate)
    }
    if processIdentifier == fixture.spotlightPID {
        guard !fixture.spotlightMissing else { return nil }
        let snapshot = FixtureRunningApplication(bundleURL: fixture.spotlightBundleURL,
            launchDate: fixture.missingLaunchDate ? nil : fixture.launchDate,
            bundleIdentifier: fixture.spotlightBundleID, executableURL: fixture.spotlightExecutableURL,
            isTerminated: fixture.spotlightTerminated)
        let callback = fixture.afterMetadataRead
        fixture.afterMetadataRead = nil
        callback?()
        return snapshot
    }
    guard processIdentifier == getpid() else { return nil }
    let snapshot = FixtureRunningApplication(bundleURL: fixture.framework.map(fixtureBundle),
                                            launchDate: fixture.missingLaunchDate ? nil : fixture.launchDate)
    let callback = fixture.afterMetadataRead
    fixture.afterMetadataRead = nil
    callback?()
    return snapshot
}
func fixtureproc_pidinfo(_ pid: Int32, _ flavor: Int32, _ arg: UInt64,
                         _ buffer: UnsafeMutableRawPointer?, _ size: Int32) -> Int32 {
    precondition(pid == fixture.spotlightPID && flavor == PROC_PIDTBSDINFO && arg == 0)
    let info = buffer!.assumingMemoryBound(to: proc_bsdinfo.self)
    info.pointee.pbi_pid = fixture.spotlightProcPID ?? UInt32(pid)
    info.pointee.pbi_start_tvsec = fixture.spotlightStartSeconds
    info.pointee.pbi_start_tvusec = fixture.spotlightStartMicroseconds
    return fixture.spotlightProcResult ?? size
}
func fixtureAXObserverCreate(_ pid: pid_t, _ callback: AXObserverCallback,
                             _ observer: UnsafeMutablePointer<AXObserver?>) -> AXError {
    fixture.observerPIDs.append(pid)
    // Own process only; notifications are never registered against any real UI.
    return AXObserverCreate(getpid(), callback, observer)
}
func fixtureAXObserverAddNotification(_ observer: AXObserver, _ element: AXUIElement,
                                     _ notification: CFString, _ context: UnsafeMutableRawPointer?) -> AXError { .success }
func fixturePostEvent(_ event: CGEvent, _ pid: pid_t) {
    precondition(pid == fixture.ownerPID, "Unicode delivery stays in captured fixture owner")
    fixture.postedPIDs.append(pid)
    guard let data = event.data, let received = CGEvent(withDataAllocator: nil, data: data),
          let native = NSEvent(cgEvent: received) else { fatalError("serialized event") }
    main {
        if received.type == .keyDown { fixture.writes += 1; fixture.editor.keyDown(with: native) }
        else { fixture.editor.keyUp(with: native) }
    }
}
func treePending() -> Bool {
    if let readyAt = fixture.enhancedReadyAt, ProcessInfo.processInfo.systemUptime >= readyAt { fixture.lazyTree = false }
    return fixture.lazyTree
}
func fixtureAXIsProcessTrusted() -> Bool { fixture.trusted }
@discardableResult
func fixtureAXUIElementSetMessagingTimeout(_ element: AXUIElement, _ seconds: Float) -> AXError {
    precondition(seconds > 0 && seconds <= 0.1, "bounded production RPC")
    return .success
}
func fixtureAXUIElementGetPid(_ element: AXUIElement, _ pid: UnsafeMutablePointer<pid_t>) -> AXError {
    if CFEqual(element, fixture.field) || CFEqual(element, fixture.other) { pid.pointee = fixture.ownerPID; return fixture.ownerError }
    if CFEqual(element, fixture.background) { pid.pointee = getpid(); return .success }
    if CFEqual(element, fixture.foreign) { pid.pointee = getpid() + 1; return .success }
    if CFEqual(element, fixture.app) { pid.pointee = getpid(); return .success }
    return .invalidUIElement
}
func fixtureAXUIElementCopyAttributeValue(_ element: AXUIElement, _ name: CFString,
                                         _ value: UnsafeMutablePointer<CFTypeRef?>) -> AXError {
    value.pointee = nil
    if CFEqual(element, AXUIElementCreateApplication(fixture.spotlightPID)) {
        if name as String == kAXFrontmostAttribute { value.pointee = fixture.spotlightFrontmost; return .success }
        if name as String == kAXFocusedUIElementAttribute { value.pointee = fixture.spotlightAppFocus; return value.pointee == nil ? .noValue : .success }
        return .attributeUnsupported
    }
    if CFEqual(element, fixture.app) {
        switch name as String {
        case kAXFrontmostAttribute: value.pointee = fixture.frontmost; return fixture.frontmostError
        case "AXEnhancedUserInterface": value.pointee = fixture.enhancedReadyAt == nil ? kCFBooleanFalse : fixture.enhancedReadback; return value.pointee == nil ? .noValue : .success
        case kAXFocusedUIElementAttribute:
            if treePending() { return .noValue }
            value.pointee = fixture.appFocus; return fixture.appError
        default: return .attributeUnsupported
        }
    }
    if CFEqual(element, fixture.system) {
        fixture.systemReads += 1
        precondition(name as String == kAXFocusedUIElementAttribute, "only own synthetic focus metadata")
        if treePending() { return .noValue }
        value.pointee = fixture.systemFocus; return fixture.systemError
    }
    if CFEqual(element, fixture.background) { fixture.backgroundReads += 1; return .noValue }
    precondition(CFEqual(element, fixture.field) || CFEqual(element, fixture.other), "no attribute read of foreign element")
    return main {
        switch name as String {
        case kAXValueAttribute: value.pointee = fixture.editor.accessibilityValue() as? CFTypeRef
        case kAXSelectedTextRangeAttribute:
            let callback = fixture.afterRangeRead
            fixture.afterRangeRead = nil
            callback?()
            if fixture.rangeNeedsTree && (fixture.enhancedReadyAt == nil || ProcessInfo.processInfo.systemUptime < fixture.enhancedReadyAt!) { return .noValue }
            let selected = fixture.editor.selectedRange()
            var range = CFRange(location: selected.location, length: selected.length)
            value.pointee = AXValueCreate(.cfRange, &range)
        case kAXRoleAttribute: value.pointee = (fixture.role ?? fixture.editor.accessibilityRole()?.rawValue) as CFString?
        case kAXSubroleAttribute: value.pointee = fixture.secureField ? kAXSecureTextFieldSubrole as CFString : fixture.editor.accessibilitySubrole()?.rawValue as CFString?
        case kAXEnabledAttribute: value.pointee = (fixture.enabled ?? (fixture.framework == nil && fixture.ownerPID != fixture.spotlightPID ? fixture.editor.isAccessibilityEnabled() : fixture.editor.isEditable)) ? kCFBooleanTrue : kCFBooleanFalse
        default: return .attributeUnsupported
        }
        return value.pointee == nil ? .noValue : .success
    }
}
func fixtureAXUIElementIsAttributeSettable(_ element: AXUIElement, _ name: CFString,
                                         _ settable: UnsafeMutablePointer<DarwinBoolean>) -> AXError {
    precondition(CFEqual(element, fixture.field))
    let writable = [kAXSelectedTextAttribute: fixture.directSettable,
                    kAXSelectedTextRangeAttribute: fixture.rangeSettable,
                    kAXValueAttribute: fixture.valueSettable]
    settable.pointee = DarwinBoolean(main { fixture.editor.isEditable } && writable[name as String] == true)
    return .success
}
func fixtureAXUIElementSetAttributeValue(_ element: AXUIElement, _ name: CFString, _ value: CFTypeRef) -> AXError {
    if CFEqual(element, AXUIElementCreateApplication(fixture.spotlightPID)) {
        precondition(name as String == "AXManualAccessibility", "only bounded accessibility activation")
        fixture.spotlightBootstrapCount += 1
        return .attributeUnsupported
    }
    if CFEqual(element, fixture.app) {
        switch name as String {
        case "AXManualAccessibility":
            fixture.bootstrapCount += 1
            if fixture.manualError == .success { fixture.lazyTree = false }
            fixture.afterManual?()
            return fixture.manualError
        case "AXEnhancedUserInterface":
            fixture.bootstrapOnMain = Thread.isMainThread
            fixture.enhancedCount += 1
            fixture.enhancedReadyAt = ProcessInfo.processInfo.systemUptime + fixture.enhancedDelay
            return fixture.enhancedError
        default: fatalError("unexpected application mutation")
        }
    }
    precondition(CFEqual(element, fixture.field))
    return main {
        switch name as String {
        case kAXSelectedTextRangeAttribute:
            fixture.selectionWrites += 1
            guard fixture.rangeSettable else { return .attributeUnsupported }
            var range = CFRange()
            guard CFGetTypeID(value) == AXValueGetTypeID(), AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cfRange, &range) else { return .illegalArgument }
            fixture.editor.setAccessibilitySelectedTextRange(NSRange(location: range.location, length: range.length))
            fixture.afterSelection?()
        case kAXSelectedTextAttribute:
            fixture.writes += 1
            fixture.directWrites += 1
            if fixture.directWriteIsNoOp { return .success }
            fixture.editor.setAccessibilitySelectedText((value as! String))
        default: fatalError("whole-field writes and other mutation are forbidden")
        }
        return .success
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
func capturedReplacement() -> Bool {
    guard let target = InputFocusGuard.Target.capture(expectedPID: getpid()) else { return false }
    let result = target.replace(range: CFRange(location: 7, length: 6), expected: "ghbdtn", with: "привет",
        originalSelection: CFRange(location: 13, length: 0), allowed: { true })
    return result == .confirmed && fixture.editor.string == "before привет after"
        && fixture.editor.selectedRange() == NSRange(location: 13, length: 0) && fixture.writes == 1
}
// The real selection capture, KeyMap conversion, transaction, capability
// classifier and Unicode construction run against raw AX RPC responses. The
// only receiving editor is this process's NSTextView; no user's UI is read.
func convertFixtureSelection() -> InputFocusGuard.ReplacementResult? {
    let converter = SelectionConverter()
    var capture: SelectionConverter.Capture?
    var request: InputFocusGuard.Permit?
    converter.capture(expectedPID: getpid()) { capture = $0; request = $1 }
    let deadline = Date().addingTimeInterval(4)
    while capture == nil && Date() < deadline { pump() }
    let selection: SelectionConverter.Selection?
    switch capture {
    case .selected(let value): selection = value
    case .empty(_, _, let word, _): selection = word
    default: selection = nil
    }
    guard let selection, let request else { return nil }
    let typist = Typist(postEvent: { _ in fatalError("manual selection must not submit") })
    var result: InputFocusGuard.ReplacementResult?
    converter.replace(selection, permit: request, typist: typist,
        replayRoute: .init(target: selection.target)) { result = $0; _ = $1 }
    while (result == nil || typist.isBusy) && Date() < deadline { pump() }
    return result
}
if ProcessInfo.processInfo.environment["MLS_REPLACEMENT_COMPATIBILITY"] != nil {
    fixture = FocusFixture()
    fixture.directSettable = false
    fixture.rangeSettable = false
    fixture.enabled = NSTextField().isEnabled
    fixture.editor.string = "мзт"
    fixture.editor.setSelectedRange(NSRange(location: 0, length: 3))
    let result = convertFixtureSelection()
    print("Already selected/no range setter: result=\(String(describing: result)); text=\(fixture.editor.string); caret=\(fixture.editor.selectedRange()); selectionWrites=\(fixture.selectionWrites); textWrites=\(fixture.writes)")
    check(result == .confirmed && fixture.editor.string == "vpn"
          && fixture.editor.selectedRange() == NSRange(location: 3, length: 0)
          && fixture.writes == 1 && fixture.selectionWrites == 0,
          "selected мзт converts to vpn without requiring an unused selection setter")
    exit(failures == 0 ? 0 : 1)
}
// Literal Spotlight overlay: menu application is frontmost, but the system
// field belongs to the canonical, live Apple Spotlight process.
func spotlightFixture() -> FocusFixture {
    let value = FocusFixture()
    value.ownerPID = value.spotlightPID
    value.appFocus = value.background
    value.missingLaunchDate = true
    value.editor.string = "ghbdtn"
    value.editor.setSelectedRange(NSRange(location: 6, length: 0))
    return value
}
fixture = spotlightFixture()
let spotlightConverter = SelectionConverter()
var spotlightCapture: SelectionConverter.Capture?
var spotlightRequest: InputFocusGuard.Permit?
spotlightConverter.capture(expectedPID: getpid()) { spotlightCapture = $0; spotlightRequest = $1 }
let spotlightCaptureDeadline = Date().addingTimeInterval(4)
while spotlightCapture == nil && Date() < spotlightCaptureDeadline { pump() }
if case .empty(let target, _, let word, _) = spotlightCapture, let word, let spotlightRequest {
    let typist = Typist(postEvent: { _ in fatalError("Option does not submit") })
    var result: InputFocusGuard.ReplacementResult?
    spotlightConverter.replace(word, permit: spotlightRequest, typist: typist,
        replayRoute: .init(target: target)) { result = $0; _ = $1 }
    let deadline = Date().addingTimeInterval(4)
    while (result == nil || typist.isBusy) && Date() < deadline { pump() }
    check(result == .confirmed && target.pid == fixture.spotlightPID
          && fixture.editor.string == "привет" && fixture.editor.selectedRange() == NSRange(location: 6, length: 0)
          && fixture.writes == 1 && fixture.bootstrapCount == 0,
          "Spotlight Option captures actual owner PID and converts ghbdtn to привет once with exact caret")
} else {
    if case .unavailable(let reason) = spotlightCapture { print("Spotlight capture: \(reason.message)") }
    check(false, "Spotlight Option captures actual owner PID and converts ghbdtn to привет once with exact caret")
}
fixture = spotlightFixture(); fixture.rangeNeedsTree = true
check(InputFocusGuard.Target.capture(expectedPID: getpid()) == nil && fixture.writes == 0
      && fixture.bootstrapCount == 0 && fixture.spotlightBootstrapCount == 0,
      "Spotlight without initial selection requires fresh capture without preparing background or stale overlay")
fixture = spotlightFixture(); fixture.rangeNeedsTree = true
if case .unavailable(.unavailableSelection) = DictationTarget.capture(expectedPID: getpid(), permit: .init()) {
    check(fixture.writes == 0 && fixture.bootstrapCount == 0 && fixture.spotlightBootstrapCount == 0,
          "dictation missing initial Spotlight range refuses delayed capture without preparation")
} else { check(false, "dictation missing initial Spotlight range refuses delayed capture without preparation") }
fixture = spotlightFixture()
fixture.afterRangeRead = { fixture.spotlightStartMicroseconds += 1 }
check(InputFocusGuard.Target.capture(expectedPID: getpid()) == nil && fixture.writes == 0 && fixture.backgroundReads == 0,
      "Spotlight process incarnation changing during initial range read refuses target publication")
fixture = FocusFixture(); fixture.systemFocus = nil; fixture.appFocus = nil
fixture.afterManual = { fixture.ownerPID = fixture.spotlightPID; fixture.systemFocus = fixture.field }
check(InputFocusGuard.Target.capture(expectedPID: getpid()) == nil && fixture.writes == 0,
      "initially missing native field cannot redirect delayed capture into newly opened Spotlight")
fixture = FocusFixture()
check(capturedReplacement(), "ordinary raw system focus authorizes exact own AppKit replacement")
fixture = FocusFixture(); fixture.frontmostError = .cannotComplete; fixture.frontmost = nil
check(capturedReplacement(), "valid system-focused field survives unavailable app-frontmost RPC")
fixture = FocusFixture(); fixture.systemFocus = fixture.foreign
check(InputFocusGuard.Target.capture(expectedPID: getpid()) == nil && fixture.writes == 0,
      "positive foreign system focus never falls back to stale application focus")
fixture = FocusFixture(); fixture.frontmost = kCFBooleanFalse
check(InputFocusGuard.Target.capture(expectedPID: getpid()) == nil && fixture.writes == 0,
      "explicit non-frontmost application stays fail-closed")
fixture = FocusFixture(); fixture.systemError = .noValue; fixture.systemFocus = nil
check(capturedReplacement(), "confirmed frontmost application can supply unavailable system focus")
fixture = FocusFixture(); fixture.lazyTree = true
check(capturedReplacement() && fixture.bootstrapCount == 1, "bounded bootstrap reacquires real raw focus path")
fixture = FocusFixture(); fixture.framework = "Codex Framework.framework"
fixture.lazyTree = true; fixture.manualError = .attributeUnsupported
var chromiumPreparation: Bool?
DispatchQueue.global().async { chromiumPreparation = capturedReplacement() }
let chromiumDeadline = Date().addingTimeInterval(5)
while chromiumPreparation == nil && Date() < chromiumDeadline { pump() }
check(chromiumPreparation == false && fixture.writes == 0, "missing initial Chromium field prepares without licensing a delayed edit")
let treeDeadline = Date().addingTimeInterval(2.6)
while Date() < treeDeadline { pump() }
check(capturedReplacement() && fixture.enhancedCount == 1,
      "Chromium 155 rejected manual bootstrap resolves delayed raw noValue and fresh request converts ghbdtn once")
fixture = FocusFixture(); fixture.framework = "Yandex Framework.framework"
fixture.lazyTree = true; fixture.manualError = .attributeUnsupported; fixture.directWriteIsNoOp = true
check(!capturedReplacement() && fixture.writes == 0,
      "Yandex missing initial field refuses text mutation while preparing accessibility")
for _ in 0..<3 { _ = InputFocusGuard.Target.capture(expectedPID: getpid()) }
check(fixture.bootstrapCount == 1 && fixture.enhancedCount == 1 && fixture.writes == 0,
      "repeated Yandex samples share the process gate without restarting activation")
let yandexTreeDeadline = Date().addingTimeInterval(2.6)
while Date() < yandexTreeDeadline { pump() }
check(capturedReplacement() && fixture.enhancedCount == 1 && fixture.directWrites == 0,
      "literal Yandex framework resolves manual unsupported plus noValue and fresh capture selects Unicode before mutation")
for framework in ["Electron Framework.framework", "Codex Framework.framework", "Chromium Framework.framework",
                  "Google Chrome Framework.framework", "Brave Browser Framework.framework",
                  "Microsoft Edge Framework.framework", "Yandex Framework.framework", "Bitrix24 Framework.framework"] {
    fixture = FocusFixture(); fixture.framework = framework; fixture.directWriteIsNoOp = true
    fixture.lazyTree = true; fixture.manualError = .attributeUnsupported; fixture.enhancedDelay = 0
    check(!capturedReplacement() && fixture.writes == 0 && fixture.enhancedCount == 1,
          "\(framework) prepares missing focus once without delayed mutation")
    check(capturedReplacement() && fixture.directWrites == 0 && fixture.enhancedCount == 1,
          "renamed app containing \(framework) uses verified Unicode on a fresh request")
}
for framework in ["Yandex Framework.framework.backup", "Not Yandex Framework.framework", "Chromium Browser.framework", "Unknown Browser Framework.framework", "Bitrix24 Framework.framework.backup"] {
    fixture = FocusFixture(); fixture.framework = framework
    check(capturedReplacement() && fixture.directWrites == 1,
          "unrecognized \(framework) retains native direct insertion")
    fixture = FocusFixture(); fixture.framework = framework
    fixture.lazyTree = true; fixture.manualError = .attributeUnsupported
    check(!capturedReplacement() && fixture.writes == 0 && fixture.enhancedCount == 0,
          "unrecognized \(framework) never receives enhanced UI")
}
func failureMessage(pid: pid_t? = getpid()) -> String {
    var message = ""
    check(InputFocusGuard.Target.capture(expectedPID: pid, failure: { message = $0.message }) == nil,
          "unavailable focus refuses target")
    return message
}
fixture = FocusFixture(); fixture.framework = "Bitrix24 Framework.framework"
fixture.editor.string = "before зщкефд after"
fixture.editor.setSelectedRange(NSRange(location: 13, length: 0))
fixture.lazyTree = true; fixture.manualError = .attributeUnsupported; fixture.directWriteIsNoOp = true
let bitrixPreparingMessage = failureMessage()
check(bitrixPreparingMessage.contains("SystemFocus=-25212; AppFocus=-25212")
      && bitrixPreparingMessage.contains("manual:-25205; enhanced:0; read:true")
      && fixture.editor.string == "before зщкефд after" && fixture.writes == 0,
      "literal Bitrix24 missing focus plus rejected manual accessibility only prepares without editing original source")
let bitrixTreeDeadline = Date().addingTimeInterval(2.6)
while Date() < bitrixTreeDeadline { pump() }
let bitrixConverter = SelectionConverter()
var bitrixCapture: SelectionConverter.Capture?
var bitrixRequest: InputFocusGuard.Permit?
bitrixConverter.capture(expectedPID: getpid()) { bitrixCapture = $0; bitrixRequest = $1 }
let bitrixCaptureDeadline = Date().addingTimeInterval(4)
while bitrixCapture == nil && Date() < bitrixCaptureDeadline { pump() }
if case .empty(_, _, let word, _) = bitrixCapture, let word, let bitrixRequest {
    let typist = Typist(postEvent: { _ in fatalError("Option does not post global keys") })
    var result: InputFocusGuard.ReplacementResult?
    bitrixConverter.replace(word, permit: bitrixRequest, typist: typist, replayRoute: .init(target: word.target)) { result = $0; _ = $1 }
    let deadline = Date().addingTimeInterval(4)
    while (result == nil || typist.isBusy) && Date() < deadline { pump() }
    check(result == .confirmed && fixture.editor.string == "before portal after"
          && fixture.editor.selectedRange() == NSRange(location: 13, length: 0)
          && fixture.enhancedCount == 1 && fixture.writes == 1 && fixture.directWrites == 0,
          "fresh Bitrix24 Option converts literal зщкефд to portal through verified Unicode once with exact full value and caret")
} else { check(false, "fresh Bitrix24 Option captures the ready original word") }
// Bootstrap compatibility and safety at the same raw OS boundary.
fixture = FocusFixture(); fixture.lazyTree = true; fixture.manualError = .attributeUnsupported
check(!capturedReplacement() && fixture.enhancedCount == 0 && fixture.writes == 0,
      "native app rejecting manual accessibility never receives enhanced UI")
fixture = FocusFixture(); fixture.framework = "Codex Framework.framework"; fixture.lazyTree = true
fixture.manualError = .attributeUnsupported; fixture.enhancedDelay = 100
let preparingMessage = failureMessage()
check(preparingMessage.contains("подготавливает") && preparingMessage.contains("SystemFocus=-25212")
    && preparingMessage.contains("manual:-25205; enhanced:0; read:true"),
    "preparing diagnostic preserves noValue and verifies alternate readback without text")
for _ in 0..<3 { _ = failureMessage() }
check(fixture.bootstrapCount == 1 && fixture.enhancedCount == 1 && fixture.writes == 0,
      "separate capture adapters do not restart a live process activation debounce")
fixture.missingLaunchDate = true
_ = failureMessage()
fixture.missingLaunchDate = false
_ = failureMessage()
check(fixture.enhancedCount == 1, "temporarily missing launch metadata cannot evict a live activation gate")
fixture.launchDate = fixture.launchDate.addingTimeInterval(1); fixture.enhancedReadyAt = nil
_ = failureMessage()
check(fixture.enhancedCount == 2, "reused PID with a new launch identity receives its own activation")
fixture = FocusFixture(); fixture.framework = "Codex Framework.framework"; fixture.lazyTree = true
fixture.manualError = .notImplemented; fixture.enhancedError = .notImplemented
fixture.enhancedReadback = kCFBooleanFalse; fixture.enhancedDelay = 0
_ = failureMessage()
check(capturedReplacement() && fixture.enhancedCount == 1,
      "alternate setter error or false flag cannot veto independently available exact field readback")
fixture = FocusFixture(); fixture.framework = "Codex Framework.framework"; fixture.lazyTree = true
fixture.manualError = .attributeUnsupported; fixture.enhancedReadback = nil; fixture.enhancedDelay = 100
let unavailableMessage = failureMessage()
check(unavailableMessage.contains("read:-25212") && fixture.writes == 0,
      "unknown alternate readback never invents a focused field")
fixture = FocusFixture(); fixture.framework = "Codex Framework.framework"; fixture.lazyTree = true
fixture.manualError = .cannotComplete
check(!capturedReplacement() && fixture.enhancedCount == 0,
      "ambiguous manual timeout does not authorize an alternate mutation")
fixture = FocusFixture(); fixture.framework = "Codex Framework.framework"; fixture.lazyTree = true
fixture.manualError = .attributeUnsupported
let converterPreparing = SelectionConverter()
var preparingCapture: SelectionConverter.Capture?
converterPreparing.capture(expectedPID: getpid()) { preparingCapture = $0; _ = $1 }
let optionPreparingDeadline = Date().addingTimeInterval(1)
while preparingCapture == nil && Date() < optionPreparingDeadline { pump() }
fixture.systemFocus = fixture.other; fixture.appFocus = fixture.other
let switchedDeadline = Date().addingTimeInterval(2.6)
while Date() < switchedDeadline { pump() }
if case .unavailable(let reason) = preparingCapture {
    check(reason.message.contains("подготавливает") && fixture.writes == 0 && !fixture.bootstrapOnMain,
          "Option with no original identity prepares off-main and cannot edit a later same-app field")
} else { check(false, "Option with no original identity refuses delayed edit") }
// A known field lacking its range can wait, but must keep that exact identity.
fixture = FocusFixture(); fixture.framework = "Codex Framework.framework"; fixture.rangeNeedsTree = true
fixture.manualError = .attributeUnsupported
var changedFieldCapture: InputFocusGuard.Target?
var changedFieldDone = false
DispatchQueue.global().async { changedFieldCapture = InputFocusGuard.Target.capture(expectedPID: getpid()); changedFieldDone = true }
let enableDeadline = Date().addingTimeInterval(1)
while fixture.enhancedCount == 0 && Date() < enableDeadline { pump() }
fixture.systemFocus = fixture.other; fixture.appFocus = fixture.other
let changedDeadline = Date().addingTimeInterval(4)
while !changedFieldDone && Date() < changedDeadline { pump() }
check(changedFieldDone && changedFieldCapture == nil && fixture.writes == 0,
      "known initial field changing during delayed bootstrap is rejected")
for framework in ["Codex Framework.framework", "Yandex Framework.framework", "Bitrix24 Framework.framework"] {
    fixture = FocusFixture(); fixture.framework = framework; fixture.rangeNeedsTree = true
    fixture.manualError = .attributeUnsupported; fixture.enhancedDelay = 100
    let cancelPermit = DictationInsertionPermit()
    var cancelledCapture: DictationTarget.Capture?
    DispatchQueue.global().async { cancelledCapture = DictationTarget.capture(expectedPID: getpid(), permit: cancelPermit) }
    let cancelEnableDeadline = Date().addingTimeInterval(1)
    while fixture.enhancedCount == 0 && Date() < cancelEnableDeadline { pump() }
    cancelPermit.cancel()
    let cancelDeadline = Date().addingTimeInterval(0.5)
    while cancelledCapture == nil && Date() < cancelDeadline { pump() }
    if case .unavailable(.changed) = cancelledCapture {
        check(fixture.writes == 0 && !fixture.bootstrapOnMain, "\(framework) dictation cancellation interrupts pending enhanced wait off-main without writes")
    } else { check(false, "\(framework) dictation cancellation interrupts pending enhanced wait") }
}
fixture = FocusFixture(); fixture.framework = "Codex Framework.framework"; fixture.rangeNeedsTree = true
fixture.manualError = .attributeUnsupported; fixture.enhancedDelay = 100
let boundedStart = ProcessInfo.processInfo.systemUptime
check(!capturedReplacement() && ProcessInfo.processInfo.systemUptime - boundedStart < 3.5
      && fixture.systemReads == 3 && fixture.enhancedCount == 1 && fixture.writes == 0,
      "unavailable delayed tree ends after bounded three focus reads and one activation")
fixture = FocusFixture(); fixture.framework = "Codex Framework.framework"; fixture.systemFocus = fixture.foreign
check(!capturedReplacement() && fixture.enhancedCount == 0 && fixture.bootstrapCount == 0,
      "positive foreign focus cannot trigger activation of the stale application")
for framework in ["Codex Framework.framework", "Yandex Framework.framework", "Bitrix24 Framework.framework"] {
    for stage in ["metadata", "manual"] {
        fixture = FocusFixture(); fixture.framework = framework; fixture.lazyTree = true
        fixture.manualError = .attributeUnsupported
        let replaceProcess = {
            fixture.launchDate = fixture.launchDate.addingTimeInterval(1)
            fixture.framework = nil
            fixture.lazyTree = false
        }
        if stage == "metadata" { fixture.afterMetadataRead = replaceProcess }
        else { fixture.afterManual = replaceProcess }
        check(!capturedReplacement() && fixture.enhancedCount == 0 && fixture.writes == 0,
              "\(framework) process replacement during \(stage) refuses enhanced UI and cannot license new process field")
    }
}
// Retain at most 32 live gates. These fake process identities never reach AX.
var capacityActivations = 0
for offset in 0..<33 {
    fixture = FocusFixture(); fixture.framework = "Codex Framework.framework"
    fixture.processID = pid_t(2_000_000 + offset); fixture.manualError = .attributeUnsupported
    otherRunningInstances[fixture.processID] = fixture.launchDate
    SystemDictationAccessibility().enableAccessibility(pid: fixture.processID)
    capacityActivations += fixture.enhancedCount
}
check(capacityActivations == 32 && fixture.enhancedCount == 0,
      "live activation gates are bounded without evicting and restarting older processes")
otherRunningInstances.removeAll()
fixture = FocusFixture(); fixture.frontmostError = .cannotComplete; fixture.frontmost = nil
fixture.systemError = .cannotComplete; fixture.systemFocus = nil
let timeoutMessage = failureMessage()
check(timeoutMessage.contains("AXFrontmost=-25204") && timeoutMessage.contains("SystemFocus=-25204"),
      "focus timeout retains exact stage and AX errors without source text")
check(!timeoutMessage.contains("ghbdtn") && !timeoutMessage.contains("before"), "diagnostic contains no editor text")
fixture = FocusFixture()
check(failureMessage(pid: nil).contains("macOS не сообщила активное приложение"), "missing foreground PID has a distinct explanation")
for (error, code) in [(AXError.attributeUnsupported, "-25205"), (.apiDisabled, "-25211"), (.notImplemented, "-25208"), (.noValue, "-25212")] {
    fixture = FocusFixture(); fixture.systemError = error; fixture.systemFocus = nil
    fixture.appError = error; fixture.appFocus = nil
    let message = failureMessage()
    check(message.contains("SystemFocus=\(code)") && message.contains("AppFocus=\(code)"), "raw unsupported/denied/no-value stages remain distinguishable: \(code)")
}
fixture = FocusFixture(); fixture.systemFocus = "not an AX element" as CFString
check(failureMessage().contains("SystemFocus=invalid-type"), "malformed positive system focus cannot authorize stale app fallback")
fixture = FocusFixture(); fixture.ownerError = .invalidUIElement
check(failureMessage().contains("SystemFocus=owner:-25202"), "unknown owner remains fail-closed and reports lookup error")
fixture = FocusFixture(); fixture.systemFocus = nil; fixture.systemError = .success
fixture.frontmost = nil; fixture.frontmostError = .success
check(failureMessage().contains("AXFrontmost=no-value; SystemFocus=no-value"), "success without returned values does not invent a target")
fixture = FocusFixture(); fixture.systemFocus = fixture.foreign
check(failureMessage().contains("SystemFocus=foreign-owner"), "foreign focus exposes metadata only")
fixture = FocusFixture(); fixture.frontmost = kCFBooleanFalse
check(failureMessage().contains("AXFrontmost=false"), "explicit inactive application has a distinct diagnostic")
fixture = FocusFixture(); fixture.trusted = false
check(failureMessage().contains("нет разрешения"), "trust failure remains separate")
fixture = FocusFixture(); fixture.secureField = true
check(failureMessage().contains("защищённое"), "secure target remains unavailable")
fixture = FocusFixture(); fixtureSecureInput = true
check(failureMessage().contains("защищённое"), "secure input remains unavailable")
fixtureSecureInput = false
for framework: String? in [nil, "Yandex Framework.framework", "Bitrix24 Framework.framework"] {
    fixture = FocusFixture(); fixture.framework = framework; fixture.editor.isEditable = false
    check(!capturedReplacement() && fixture.writes == 0 && fixture.editor.string == "before ghbdtn after",
          "\(framework ?? "native") read-only control cannot authorize a write")
}
fixture = FocusFixture()
let captured = InputFocusGuard.Target.capture(expectedPID: getpid())!
fixture.systemFocus = fixture.foreign
let foreignResult = captured.replace(range: CFRange(location: 7, length: 6), expected: "ghbdtn", with: "привет",
    originalSelection: CFRange(location: 13, length: 0), allowed: { true })
check(foreignResult == .untouched && fixture.writes == 0 && fixture.editor.string == "before ghbdtn after", "system focus change after capture blocks old target")
fixture = FocusFixture()
fixture.afterSelection = { fixture.frontmost = kCFBooleanFalse }
check(!capturedReplacement() && fixture.writes == 0 && fixture.editor.string == "before ghbdtn after", "frontend change during selection blocks text mutation")
fixture = FocusFixture()
let cancelledTarget = InputFocusGuard.Target.capture(expectedPID: getpid())!
let permit = InputFocusGuard.Permit()
fixture.afterSelection = { permit.cancel() }
check(cancelledTarget.replace(range: CFRange(location: 7, length: 6), expected: "ghbdtn", with: "привет",
    originalSelection: CFRange(location: 13, length: 0), allowed: { permit.isAllowed }) == .untouched
    && fixture.writes == 0 && fixture.editor.string == "before ghbdtn after", "cancellation after selection preserves source")
for framework: String? in [nil, "Yandex Framework.framework", "Codex Framework.framework", "Bitrix24 Framework.framework"] {
    for kind in ["word", "selected", "empty"] {
        fixture = FocusFixture(); fixture.frontmostError = .cannotComplete; fixture.frontmost = nil
        fixture.framework = framework; fixture.directWriteIsNoOp = framework != nil
        if kind == "selected" { fixture.editor.setSelectedRange(NSRange(location: 7, length: 6)) }
        if kind == "empty" { fixture.editor.string = ""; fixture.editor.setSelectedRange(NSRange(location: 0, length: 0)) }
        let converter = SelectionConverter()
        var capture: SelectionConverter.Capture?
        var request: InputFocusGuard.Permit?
        converter.capture(expectedPID: getpid()) { capture = $0; request = $1 }
        let deadline = Date().addingTimeInterval(4)
        while capture == nil && Date() < deadline { pump() }
        var selection: SelectionConverter.Selection?
        switch capture {
        case .selected(let value): selection = value
        case .empty(_, _, let word, _): selection = word
        default: break
        }
        if kind == "empty" {
            if case .empty = capture { check(selection == nil && fixture.writes == 0, "empty Option capture retains layout-only route") }
            else { check(false, "empty Option capture retains layout-only route") }
        } else if let selection, let request {
            let typist = Typist(postEvent: { _ in fatalError("Option does not post global keys") })
            var result: InputFocusGuard.ReplacementResult?
            converter.replace(selection, permit: request, typist: typist, replayRoute: .init(target: selection.target)) { result = $0; _ = $1 }
            let writeDeadline = Date().addingTimeInterval(4)
            while (result == nil || typist.isBusy) && Date() < writeDeadline { pump() }
            check(result == .confirmed && fixture.editor.string == "before привет after" && fixture.writes == 1
                  && fixture.editor.selectedRange() == NSRange(location: 13, length: 0)
                  && fixture.directWrites == (framework == nil ? 1 : 0),
                  "\(framework ?? "native") production Option \(kind) captures raw focus and converts literal ghbdtn once with exact caret")
        } else { check(false, "\(framework ?? "native") production Option \(kind) raw focus capture") }
    }
}
for framework: String? in [nil, "Yandex Framework.framework", "Codex Framework.framework", "Bitrix24 Framework.framework"] {
    for (label, key, flags) in [("Space", CGKeyCode(49), CGEventFlags()), ("Enter", 36, CGEventFlags()),
                                ("ShiftEnter", 36, CGEventFlags.maskShift), ("Tab", 48, CGEventFlags())] {
        fixture = FocusFixture(); fixture.frontmostError = .cannotComplete; fixture.frontmost = nil
        fixture.framework = framework; fixture.directWriteIsNoOp = framework != nil
        guard let target = InputFocusGuard.Target.capture(expectedPID: getpid()) else {
            check(false, "automatic \(label) target through raw focus"); continue
        }
        let ticket = InputFocusGuard.Ticket(target: target, permit: .init(), replacementPermit: .init(), replayRoute: .init(target: target))
        var posted: [CGEvent] = []
        let typist = Typist(postEvent: { posted.append(CGEvent(withDataAllocator: nil, data: $0.data!)!) })
        var result: InputFocusGuard.ReplacementResult?
        typist.replaceLastWord(expected: "ghbdtn", with: "привет", ticket: ticket,
            separator: Typist.makeKeyPress(keyCode: key, flags: flags), separatorCharacter: key == 49 ? " " : (key == 48 ? "\t" : "\n"), navigates: key != 49) { result = $0 }
        let deadline = Date().addingTimeInterval(4)
        while (result == nil || typist.isBusy) && Date() < deadline { pump() }
        check(result == .confirmed && fixture.editor.string == (key == 49 ? "before привет  after" : "before привет after")
            && fixture.writes == 1 && fixture.directWrites == (framework == nil ? 1 : 0)
            && fixture.editor.selectedRange() == NSRange(location: key == 49 ? 14 : 13, length: 0)
            && posted.count == (key == 49 ? 0 : 2), "\(framework ?? "native") automatic \(label) preserves full value, exact caret and once-only separator")
        if key != 49 { check(posted.allSatisfy { $0.getIntegerValueField(.keyboardEventKeycode) == key && $0.flags == flags }, "\(label) key and flags preserved") }
    }
}
fixture = FocusFixture(); fixture.frontmostError = .cannotComplete; fixture.frontmost = nil
fixture.systemError = .cannotComplete; fixture.systemFocus = nil
switch DictationTarget.capture(expectedPID: getpid(), permit: .init()) {
case .unavailable(let failure):
    check(failure.message.contains("AXFrontmost=-25204") && failure.message.contains("SystemFocus=-25204"), "dictation exposes the same raw focus diagnostic before observation or insertion")
case .target: check(false, "failed raw dictation focus may not invent a target")
}
// Spotlight uses the same raw boundary as native/Chromium. Only the metadata
// and AX responses differ; every text/caret result comes from owned AppKit.
for (label, change) in [
    ("wrong bundle ID", { fixture.spotlightBundleID = "com.example.Spotlight" }),
    ("lookalike bundle path", { fixture.spotlightBundleURL = URL(fileURLWithPath: "/Applications/Spotlight.app") }),
    ("lookalike executable path", { fixture.spotlightExecutableURL = URL(fileURLWithPath: "/tmp/Spotlight") }),
    ("terminated process", { fixture.spotlightTerminated = true }),
    ("missing process", { fixture.spotlightMissing = true }),
    ("missing kernel start", { fixture.spotlightStartSeconds = 0 }),
    ("kernel lookup failure", { fixture.spotlightProcResult = 0 }),
    ("truncated kernel metadata", { fixture.spotlightProcResult = 135 }),
    ("wrong kernel PID", { fixture.spotlightProcPID = UInt32(getpid()) }),
    ("invalid kernel microseconds", { fixture.spotlightStartMicroseconds = 1_000_000 }),
    ("malformed system focus", { fixture.systemFocus = "not an element" as CFString }),
    ("unknown system owner", { fixture.ownerError = .invalidUIElement }),
    ("secure field", { fixture.secureField = true })
] as [(String, () -> Void)] {
    fixture = spotlightFixture(); change()
    check(InputFocusGuard.Target.capture(expectedPID: getpid()) == nil && fixture.writes == 0
          && fixture.bootstrapCount == 0 && fixture.spotlightBootstrapCount == 0 && fixture.backgroundReads == 0,
          "Spotlight \(label) refuses initial capture without stale background field or preparation")
}
fixture = spotlightFixture()
check(SystemDictationAccessibility().focusedElement(pid: getpid()) == nil,
      "strict resolver still rejects valid Spotlight as foreign to the old menu application PID")
fixture = spotlightFixture(); fixture.systemFocus = nil; fixture.appFocus = fixture.field
check(SystemDictationAccessibility().focusedElement(pid: fixture.spotlightPID) == nil,
      "inactive Spotlight never uses stale application focus when system focus is missing")
for (label, change) in [
    ("closed overlay", { fixture.systemFocus = fixture.background }),
    ("stale active Spotlight app-focus", { fixture.spotlightFrontmost = kCFBooleanTrue; fixture.systemFocus = nil; fixture.spotlightAppFocus = fixture.field }),
    ("same-owner new element", { fixture.systemFocus = fixture.other }),
    ("different owner", { fixture.systemFocus = fixture.foreign }),
    ("new kernel start seconds", { fixture.spotlightStartSeconds += 1 }),
    ("new kernel start microseconds", { fixture.spotlightStartMicroseconds += 1 }),
    ("lost process metadata", { fixture.spotlightProcResult = 0 }),
    ("process terminated", { fixture.spotlightTerminated = true }),
    ("identity changed", { fixture.spotlightBundleID = "com.example.Other" })
] as [(String, () -> Void)] {
    fixture = spotlightFixture()
    if let target = InputFocusGuard.Target.capture(expectedPID: getpid()) {
        change()
        let result = target.replace(range: CFRange(location: 0, length: 6), expected: "ghbdtn", with: "привет",
            originalSelection: CFRange(location: 6, length: 0), allowed: { true })
        check(result == .untouched && fixture.writes == 0 && fixture.editor.string == "ghbdtn"
              && fixture.backgroundReads == 0 && !target.isCurrent(),
              "captured Spotlight \(label) cannot redirect old replacement")
    } else { check(false, "capture before Spotlight \(label)") }
}
fixture = spotlightFixture()
if let target = InputFocusGuard.Target.capture(expectedPID: getpid()) {
    fixture.spotlightFrontmost = kCFBooleanTrue
    check(target.isCurrent(), "captured Spotlight can become AXFrontmost while exact system field stays current")
    fixture.spotlightStartMicroseconds += 1
    check(!target.isCurrent(), "frontmost Spotlight still checks captured process incarnation")
} else { check(false, "capture before Spotlight becomes AXFrontmost") }
for frontmost in [kCFBooleanTrue as CFTypeRef?, nil] {
    fixture = spotlightFixture(); fixture.spotlightFrontmost = frontmost
    if let target = InputFocusGuard.Target.capture(expectedPID: fixture.spotlightPID) {
        check(target.isCurrent(), "initial same-PID Spotlight exact system focus is current with true or missing AXFrontmost")
        fixture.spotlightStartMicroseconds += 1
        check(!target.isCurrent(), "initial same-PID Spotlight rejects changed kernel process incarnation")
    } else { check(false, "initial same-PID Spotlight captures exact system field") }
}
fixture = spotlightFixture(); fixture.spotlightFrontmost = kCFBooleanTrue
fixture.systemFocus = nil; fixture.spotlightAppFocus = fixture.field
check(InputFocusGuard.Target.capture(expectedPID: fixture.spotlightPID) == nil
      && fixture.bootstrapCount == 0 && fixture.spotlightBootstrapCount == 0,
      "initial frontmost Spotlight rejects stale app-only focus without preparing it")
fixture = spotlightFixture(); fixture.spotlightFrontmost = kCFBooleanTrue
fixture.spotlightProcResult = 0
check(InputFocusGuard.Target.capture(expectedPID: fixture.spotlightPID) == nil,
      "initial frontmost Spotlight without valid process identity stays unavailable")
fixture = spotlightFixture(); fixture.spotlightFrontmost = kCFBooleanTrue
switch DictationTarget.capture(expectedPID: fixture.spotlightPID, permit: .init()) {
case .target(let target):
    fixture.spotlightStartMicroseconds += 1
    check(!target.isCurrent(), "dictation initial same-PID Spotlight rejects changed kernel process incarnation")
case .unavailable: check(false, "dictation initial same-PID Spotlight captures exact system field")
}
for frontmost in [kCFBooleanTrue as CFTypeRef?, nil] {
    fixture = spotlightFixture(); fixture.spotlightFrontmost = frontmost; fixture.spotlightMissing = true
    check(InputFocusGuard.Target.capture(expectedPID: fixture.spotlightPID) == nil && fixture.writes == 0
          && fixture.bootstrapCount == 0 && fixture.spotlightBootstrapCount == 0,
          "initial same-PID missing running process cannot become an ordinary unstamped target")
}
fixture = spotlightFixture(); fixture.spotlightFrontmost = kCFBooleanTrue; fixture.spotlightMissing = true
fixture.systemFocus = nil; fixture.spotlightAppFocus = fixture.field
check(InputFocusGuard.Target.capture(expectedPID: fixture.spotlightPID) == nil,
      "initial same-PID missing process cannot authorize stale application focus")
for kind in ["selected", "word Unicode", "read-only", "cancelled"] {
    fixture = spotlightFixture()
    fixture.directSettable = kind != "word Unicode"
    if kind == "selected" { fixture.editor.setSelectedRange(NSRange(location: 0, length: 6)) }
    if kind == "read-only" { fixture.editor.isEditable = false }
    let converter = SelectionConverter()
    var capture: SelectionConverter.Capture?
    var request: InputFocusGuard.Permit?
    converter.capture(expectedPID: getpid()) { capture = $0; request = $1 }
    let deadline = Date().addingTimeInterval(4)
    while capture == nil && Date() < deadline { pump() }
    var selection: SelectionConverter.Selection?
    switch capture {
    case .selected(let value): selection = value
    case .empty(_, _, let word, _): selection = word
    default: break
    }
    if let selection, let request {
        if kind == "cancelled" { request.cancel() }
        let typist = Typist(postEvent: { _ in fatalError("Option never submits") })
        var result: InputFocusGuard.ReplacementResult?
        converter.replace(selection, permit: request, typist: typist, replayRoute: .init(target: selection.target)) { result = $0; _ = $1 }
        let deadline = Date().addingTimeInterval(4)
        while (result == nil || typist.isBusy) && Date() < deadline { pump() }
        let refused = kind == "read-only" || kind == "cancelled"
        check(result == (refused ? .untouched : .confirmed) && fixture.editor.string == (refused ? "ghbdtn" : "привет")
              && fixture.editor.selectedRange() == NSRange(location: 6, length: 0)
              && fixture.writes == (refused ? 0 : 1) && fixture.backgroundReads == 0
              && selection.target.pid == fixture.spotlightPID
              && (kind != "word Unicode" || fixture.postedPIDs == [fixture.spotlightPID, fixture.spotlightPID]),
              "Spotlight Option \(kind) keeps exact text/caret and actual owner routing")
        print("Spotlight \(kind): pid=\(selection.target.pid), text=\(fixture.editor.string), caret=\(fixture.editor.selectedRange()), unicodePIDs=\(fixture.postedPIDs)")
    } else { check(false, "Spotlight Option \(kind) raw capture") }
}
for (label, key, flags) in [("Space", CGKeyCode(49), CGEventFlags()), ("Enter", 36, CGEventFlags()),
                            ("ShiftEnter", 36, CGEventFlags.maskShift)] {
    fixture = spotlightFixture()
    guard let target = InputFocusGuard.Target.capture(expectedPID: getpid()) else {
        check(false, "Spotlight automatic \(label) raw capture"); continue
    }
    let ticket = InputFocusGuard.Ticket(target: target, permit: .init(), replacementPermit: .init(), replayRoute: .init(target: target))
    var posted: [CGEvent] = []
    var receivers: [pid_t] = []
    let typist = Typist(postEvent: {
        posted.append(CGEvent(withDataAllocator: nil, data: $0.data!)!)
        receivers.append(fixture.ownerPID)
    })
    var result: InputFocusGuard.ReplacementResult?
    typist.replaceLastWord(expected: "ghbdtn", with: "привет", ticket: ticket,
        separator: Typist.makeKeyPress(keyCode: key, flags: flags), separatorCharacter: key == 49 ? " " : "\n", navigates: key != 49) { result = $0 }
    let deadline = Date().addingTimeInterval(4)
    while (result == nil || typist.isBusy) && Date() < deadline { pump() }
    check(result == .confirmed && fixture.editor.string == (key == 49 ? "привет " : "привет")
          && fixture.editor.selectedRange() == NSRange(location: key == 49 ? 7 : 6, length: 0)
          && fixture.writes == 1 && fixture.backgroundReads == 0 && target.pid == fixture.spotlightPID
          && posted.count == (key == 49 ? 0 : 2) && receivers.allSatisfy { $0 == target.pid }
          && posted.allSatisfy { $0.getIntegerValueField(.keyboardEventKeycode) == key && $0.flags == flags },
          "Spotlight automatic \(label) keeps full value/caret and only original separator key pair")
    print("Spotlight auto\(label): pid=\(target.pid), text=\(fixture.editor.string), caret=\(fixture.editor.selectedRange()), keyPairs=\(posted.count / 2), receiverPIDs=\(receivers)")
}
for kind in ["direct", "Unicode", "changed process", "cancelled"] {
    fixture = spotlightFixture(); fixture.editor.string = ""; fixture.editor.setSelectedRange(NSRange(location: 0, length: 0))
    fixture.directSettable = kind != "Unicode"
    let permit = DictationInsertionPermit()
    switch DictationTarget.capture(expectedPID: getpid(), permit: permit) {
    case .target(let target):
        if kind == "changed process" { fixture.spotlightStartMicroseconds += 1 }
        if kind == "cancelled" { permit.cancel() }
        let result = target.insert("привет", permit: permit)
        let refused = kind == "changed process" || kind == "cancelled"
        check(result == (refused ? .fallback(.changed) : .inserted)
              && fixture.editor.string == (refused ? "" : "привет")
              && fixture.editor.selectedRange() == NSRange(location: refused ? 0 : 6, length: 0)
              && fixture.writes == (refused ? 0 : 1) && fixture.backgroundReads == 0
              && target.pid == fixture.spotlightPID && fixture.observerPIDs == [fixture.spotlightPID]
              && (kind != "Unicode" || fixture.postedPIDs == [fixture.spotlightPID, fixture.spotlightPID]),
              "Spotlight dictation \(kind) shares actual-owner capture/observation and exact insertion checks")
        print("Spotlight dictation\(kind): pid=\(target.pid), text=\(fixture.editor.string), caret=\(fixture.editor.selectedRange()), observerPIDs=\(fixture.observerPIDs), unicodePIDs=\(fixture.postedPIDs)")
    case .unavailable(let reason): check(false, "Spotlight dictation \(kind): \(reason.message)")
    }
}

if failures > 0 { exit(1) }
print("System focus harness passed; raw AX faults and own AppKit only, not live WindowServer acceptance.")
