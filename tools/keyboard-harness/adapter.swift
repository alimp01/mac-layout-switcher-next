import AppKit
import ApplicationServices
import SwitcherCore

// The real adapter is compiled, but these fixtures never post to other apps.
enum EventTap { static let syntheticMarker: Int64 = 0xC0FFEE }
func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
final class FixtureAX: DictationAccessibility {
    let editor = NSTextView()
    let element = AXUIElementCreateApplication(getpid())
    var isTrusted = true
    var isSecure = false
    var focused = true
    var lazyTree = false
    var hasRange = true
    var invalidRange = false
    var direct = true
    var unicode = true
    var preferUnicode = false
    var notifications = true
    var writes = 0
    var posts = 0
    var delayedNotifications = false
    var pendingNotifications = false
    var ignoreWrite = false
    var selectionReturnsFailure = false
    var refuseRestoration = false
    var values: [String] = []
    var partialWrite = false
    var deletionOnly = false
    var callback: ((DictationAXChange) -> Void)?
    var afterPost: (() -> Void)?
    var afterSelection: (() -> Void)?
    var realUnicodeEvents = 0
    init() { editor.string = "До старый после"; editor.setSelectedRange(NSRange(location: 3, length: 6)) }
    func focusedElement(pid: pid_t) -> AXUIElement? { focused && !lazyTree ? element : nil }
    func enableAccessibility(pid: pid_t) { lazyTree = false }
    func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        switch name {
        case kAXValueAttribute:
            if !values.isEmpty { return values.removeFirst() as CFString }
            return editor.string as CFString
        case kAXSelectedTextRangeAttribute:
            guard hasRange else { return nil }
            let ns = editor.selectedRange()
            var range = invalidRange ? CFRange(location: Int.max, length: Int.max) : CFRange(location: ns.location, length: ns.length)
            return AXValueCreate(.cfRange, &range)
        case kAXRoleAttribute: return kAXTextAreaRole as CFString
        default: return nil
        }
    }
    func selectedTextIsSettable(_ element: AXUIElement) -> Bool { direct }
    func supportsUnicodeInsertion(_ element: AXUIElement) -> Bool { unicode }
    func prefersUnicodeInsertion(pid: pid_t) -> Bool { preferUnicode }
    func setSelectedText(_ text: String, in element: AXUIElement) -> AXError {
        writes += 1
        if !ignoreWrite {
            let start = editor.selectedRange().location
            editor.setAccessibilitySelectedText(deletionOnly ? "" : (partialWrite ? String(text.prefix(3)) : text))
            if partialWrite { editor.setSelectedRange(NSRange(location: start, length: 3)) }
        }
        callback?(.selection)
        return partialWrite ? .cannotComplete : .success
    }
    func postUnicode(_ text: String, pid: pid_t) -> Bool {
        posts += 1
        // A previous write can be read back before its notifications reach the
        // main run loop. Deliver them after the next write has been scheduled.
        if pendingNotifications { callback?(.selection); callback?(.value); pendingNotifications = false }
        if !ignoreWrite {
            // Keep the production event construction, CG serialization and
            // AppKit text-input interpretation. Only delivery to the process
            // is replaced; successful insertion is never assigned directly.
            let transport = SystemDictationAccessibility(postEvent: { event, actualPID in
                require(actualPID == pid, "Unicode pair targets captured process")
                guard let data = event.data,
                      let received = CGEvent(withDataAllocator: nil, data: data),
                      let native = NSEvent(cgEvent: received) else { fatalError("event serialization") }
                self.realUnicodeEvents += 1
                if received.type == .keyDown {
                    if self.deletionOnly { self.editor.insertText("", replacementRange: self.editor.selectedRange()) }
                    else if self.partialWrite { self.editor.insertText(String(text.prefix(3)), replacementRange: self.editor.selectedRange()) }
                    else { self.editor.keyDown(with: native) }
                } else { self.editor.keyUp(with: native) }
            })
            require(transport.postUnicode(text, pid: pid), "production Unicode event construction succeeds")
        }
        if delayedNotifications { pendingNotifications = true }
        else { callback?(.selection); callback?(.value) }
        afterPost?()
        return true
    }
    func setSelection(_ range: CFRange, in element: AXUIElement) -> Bool {
        if refuseRestoration && range.length == 0 { return false }
        editor.setSelectedRange(NSRange(location: range.location, length: range.length))
        afterSelection?()
        return !selectionReturnsFailure
    }
    func observe(_ element: AXUIElement, pid: pid_t, changed: @escaping (DictationAXChange) -> Void) -> AnyObject? {
        callback = changed
        return notifications ? NSObject() : nil
    }
    func capture(_ permit: DictationInsertionPermit) -> DictationTarget.Capture {
        DictationTarget.capture(expectedPID: getpid(), permit: permit, accessibility: self)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
func fixture() -> (FixtureAX, InputFocusGuard.Target) {
    let ax = FixtureAX()
    ax.editor.string = "before ghbdtn after"
    ax.editor.setSelectedRange(NSRange(location: 13, length: 0))
    return (ax, InputFocusGuard.Target(element: ax.element, pid: getpid(), accessibility: ax))
}
func replace(_ target: InputFocusGuard.Target, allowed: () -> Bool = { true }) -> InputFocusGuard.ReplacementResult {
    target.replace(range: CFRange(location: 7, length: 6), expected: "ghbdtn", with: "привет",
                   originalSelection: CFRange(location: 13, length: 0), allowed: allowed)
}
let (noOp, noOpTarget) = fixture()
noOp.ignoreWrite = true
require(replace(noOpTarget) == .uncertain, "no-op selected-text setter must not report success")
require(noOp.writes == 1 && noOp.posts == 0, "uncertain write must not retry")
require(noOp.editor.selectedRange() == NSRange(location: 13, length: 0), "no-op write restores its temporary selection before queued typing")
print("PASS: no-op setter is uncertain, no retry")
let (lazy, _) = fixture()
lazy.lazyTree = true
require(InputFocusGuard.Target.capture(expectedPID: getpid(), accessibility: lazy) != nil, "lazy editor must bootstrap")
print("PASS: lazy AX capture")
let (unicode, unicodeTarget) = fixture()
unicode.direct = false
require(replace(unicodeTarget) == .confirmed, "missing setter uses verified Unicode")
require(unicode.editor.string == "before привет after" && unicode.editor.selectedRange() == NSRange(location: 13, length: 0), "exact replacement and collapsed caret")
require(unicode.realUnicodeEvents == 2, "real production down/up pair interpreted by AppKit")
print("PASS: verified Unicode without setter")
let (direct, directTarget) = fixture()
require(replace(directTarget) == .confirmed, "native selected text replacement")
require(direct.editor.string == "before привет after", "native exact replacement")
require(directTarget.sourceRange("ивет") == nil, "reject suffix of longer word")
print("PASS: native replacement and prefix boundary")
let (cancelled, cancelledTarget) = fixture()
require(replace(cancelledTarget, allowed: { false }) == .untouched && cancelled.writes == 0 && cancelled.posts == 0, "cancelled permit cannot write")
cancelled.focused = false
require(replace(cancelledTarget) == .untouched, "changed focus cannot write")
print("PASS: sticky permission and focus guards")
for mode in ["cancelled", "focus", "selection", "source", "capability"] {
    let (ax, target) = fixture()
    switch mode {
    case "focus": ax.focused = false
    case "selection": ax.editor.setSelectedRange(NSRange(location: 12, length: 0))
    case "source": ax.editor.string = "before edited after"; ax.editor.setSelectedRange(NSRange(location: 13, length: 0))
    case "capability": ax.direct = false; ax.unicode = false
    default: break
    }
    let before = ax.editor.string, caret = ax.editor.selectedRange()
    var reason: InputFocusGuard.ReplacementFailure?
    let outcome = target.replace(range: CFRange(location: 7, length: 6), expected: "ghbdtn", with: "привет",
        originalSelection: CFRange(location: 13, length: 0), capturedValue: "before ghbdtn after",
        failure: { reason = $0 }, allowed: { mode != "cancelled" })
    require(outcome == .untouched && ax.editor.string == before && ax.editor.selectedRange() == caret
            && ax.writes == 0 && ax.posts == 0, "\(mode) rejection leaves exact field state without writes")
    require(reason?.rawValue == mode && reason?.message.contains("replace.\(mode)") == true
            && reason?.message.contains("ghbdtn") == false && reason?.message.contains("привет") == false,
            "\(mode) reports actual content-free guard, not a later probe")
}
print("PASS: distinct actual rejection stages preserve source and caret without retry")
for mode in ["source", "focus", "cancelled"] {
    let (ax, target) = fixture()
    let permit = InputFocusGuard.Permit()
    if mode == "source" {
        // The preflight reads agree; the first confirmation read reports an
        // external source change. This must not blame a range setter timeout.
        ax.values = ["before ghbdtn after", "before ghbdtn after", "before edited after"]
    } else {
        ax.afterSelection = { if mode == "focus" { ax.focused = false } else { permit.cancel() } }
    }
    var reason: InputFocusGuard.ReplacementFailure?
    let outcome = target.replace(range: CFRange(location: 7, length: 6), expected: "ghbdtn", with: "привет",
        originalSelection: CFRange(location: 13, length: 0), failure: { reason = $0 }, allowed: { permit.isAllowed })
    require(outcome != .confirmed && ax.editor.string == "before ghbdtn after" && ax.writes == 0 && ax.posts == 0,
            "\(mode) during selection confirmation preserves source without text writes")
    require(reason?.rawValue == mode, "selection confirmation reports actual \(mode) guard instead of selectionWrite")
}
print("PASS: confirmation retains actual source/focus/cancellation rejection stage")
let (partial, partialTarget) = fixture()
partial.direct = false; partial.partialWrite = true
require(replace(partialTarget) == .uncertain && partial.posts == 1, "partial Unicode must stop without retry")
let route = InputFocusGuard.ReplayRoute(target: partialTarget)
let permit = InputFocusGuard.Permit()
route.didBecomeUncertain()
require(!route.canReplay(permit: permit, navigates: true), "uncertain write blocks queued Enter and Tab")
require(route.canReplay(permit: permit), "ordinary physical characters remain deliverable")
print("PASS: partial write and navigation disposition")
let (selection, selectedTarget) = fixture()
selection.editor.setSelectedRange(NSRange(location: 7, length: 6))
require(selectedTarget.replace(range: CFRange(location: 7, length: 6), expected: "ghbdtn", with: "привет", originalSelection: CFRange(location: 7, length: 6), allowed: { true }) == .confirmed, "explicit selection conversion")
print("PASS: selected text")
print("Keyboard adapter harness passed (mock AX boundary, own NSTextView; not cross-app delivery).")

let (timeout, timeoutTarget) = fixture()
timeout.selectionReturnsFailure = true
require(replace(timeoutTarget) == .confirmed, "selection timeout after applying range must be verified, not replay space into selected source")
let (restoration, restorationTarget) = fixture()
restoration.ignoreWrite = true; restoration.refuseRestoration = true
require(replace(restorationTarget) == .unconfirmedSelection, "failed caret restoration keeps selection uncertain")
let restorationRoute = InputFocusGuard.ReplayRoute(target: restorationTarget)
restorationRoute.didBecomeUncertain()
require(!restorationRoute.canReplay(permit: InputFocusGuard.Permit()), "queued typing cannot replace uncertain selection")
print("PASS: selection timeout and failed restoration")
let (stale, staleTarget) = fixture()
stale.editor.string = "before xghbdtn after"
stale.editor.setSelectedRange(NSRange(location: 14, length: 0))
require(staleTarget.replace(range: CFRange(location: 8, length: 6), expected: "ghbdtn", with: "привет", originalSelection: CFRange(location: 14, length: 0), requiresWordBoundary: true, allowed: { true }) == .untouched, "word boundary must be validated again in write snapshot")
let (racy, racyTarget) = fixture()
racy.values = ["before ozonxx after"]
require(replace(racyTarget) == .untouched && racy.writes == 0, "changed source in write snapshot cannot be selected/written")
print("PASS: stale prefix and same-snapshot source guard")
let (cold, coldTarget) = fixture()
let coldWord = coldTarget.wordBeforeCaret(CFRange(location: 13, length: 0))
require(coldWord?.text == "ghbdtn" && coldWord?.range.location == 7, "Option recovers preexisting word after cold binding")
cold.editor.string = "ghbdtn  "; cold.editor.setSelectedRange(NSRange(location: 8, length: 0))
require(coldTarget.wordBeforeCaret(CFRange(location: 8, length: 0))?.text == "ghbdtn  ", "manual fallback preserves trailing spaces")
cold.editor.string = ""; cold.editor.setSelectedRange(NSRange(location: 0, length: 0))
require(coldTarget.wordBeforeCaret(CFRange(location: 0, length: 0)) == nil, "empty field has no conversion candidate")
cold.editor.string = String(repeating: " ", count: 5000); cold.editor.setSelectedRange(NSRange(location: 5000, length: 0))
require(coldTarget.wordBeforeCaret(CFRange(location: 5000, length: 0)) == nil, "whitespace scan bounded")
print("PASS: cold word, empty field and bounded scan")
func drain(_ typist: Typist, done: @escaping () -> Bool) {
    let deadline = Date().addingTimeInterval(4)
    while (!done() || typist.isBusy) && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
    RunLoop.current.run(until: Date().addingTimeInterval(0.03))
    require(done() && !typist.isBusy, "Typist queue completes")
}
func ticket(_ target: InputFocusGuard.Target) -> InputFocusGuard.Ticket {
    .init(target: target, permit: .init(), replacementPermit: .init(), replayRoute: .init(target: target))
}
let (ordered, orderedTarget) = fixture()
let orderedTicket = ticket(orderedTarget)
var posts: [(CGEventType, Int64, CGEventFlags, String)] = []
let typist = Typist(postEvent: { event in
    posts.append((event.type, event.getIntegerValueField(.keyboardEventKeycode), event.flags, ordered.editor.string))
})
let enter = Typist.makeKeyPress(keyCode: Typist.returnKeyCode, flags: .maskShift)!
var completed = false
typist.replaceLastWord(expected: "ghbdtn", with: "привет", ticket: orderedTicket, separator: enter, separatorCharacter: "\n", navigates: true) { result in
    require(result == .confirmed, "Typist confirms replacement before Enter"); completed = true
}
typist.send(Typist.makeUnicodePress("x")!, ticket: orderedTicket)
drain(typist, done: { completed })
require(posts.count == 4 && posts[0].1 == 36 && posts[0].2.contains(.maskShift), "Shift+Enter flags and down/up order preserved")
require(posts[0].3 == "before привет after" && posts[2].1 == 0, "replacement completes before separator and subsequent key")
print("PASS: production Typist Shift+Enter and fast key ordering")
let (failed, failedTarget) = fixture()
failed.ignoreWrite = true
let failedTicket = ticket(failedTarget)
var sent = 0; var recovery = ""; var finished = false
let failedTypist = Typist(postEvent: { _ in sent += 1 })
failedTypist.onWithheldInput = { recovery += $0 }
failedTypist.replaceLastWord(expected: "ghbdtn", with: "привет", ticket: failedTicket,
 separator: Typist.makeKeyPress(keyCode: 49, flags: [])!, separatorCharacter: " ", navigates: false) { result in
    require(result == .uncertain, "no-op queued replacement uncertain")
}
failedTypist.send(enter, ticket: failedTicket, navigates: true)
failedTypist.replaceLastWord(expected: "next", with: "след", ticket: failedTicket,
 separator: Typist.makeKeyPress(keyCode: 48, flags: [])!, separatorCharacter: "\t", navigates: true) { result in
    require(result == .untouched, "dependent correction rejected"); finished = true
}
failedTypist.send(Typist.makeUnicodePress("x")!, ticket: failedTicket)
drain(failedTypist, done: { finished })
require(sent == 2 && recovery == " ⏎⇥", "both queued navigation paths retained; ordinary key follows restored caret")
print("PASS: production queue retains uncertain/dependent separators, preserves ordinary key")
let (partialDirect, partialDirectTarget) = fixture()
partialDirect.partialWrite = true
let partialTicket = ticket(partialDirectTarget)
var partialRecovery = ""; var partialDone = false; var partialSent = 0
let partialTypist = Typist(postEvent: { _ in partialSent += 1 })
partialTypist.onWithheldInput = { partialRecovery += $0 }
partialTypist.replaceLastWord(expected: "ghbdtn", with: "привет", ticket: partialTicket,
 separator: nil, separatorCharacter: nil, navigates: false) { _ in partialDone = true }
partialTypist.send(Typist.makeUnicodePress("x")!, ticket: partialTicket)
drain(partialTypist, done: { partialDone })
require(partialSent == 0 && partialRecovery == "x", "typing over partial selected mutation retained, never overwrites source")
print("PASS: partial selected write retains queued text")

let (deleted, deletedTarget) = fixture()
deleted.deletionOnly = true
let deletedTicket = ticket(deletedTarget)
var deletedDone = false; var deletedSent = 0
var savedOriginal = ""; var savedReplacement = ""; var savedKeys = ""
let deletedTypist = Typist(postEvent: { _ in deletedSent += 1 })
deletedTypist.onUnconfirmedReplacement = { savedOriginal = $0; savedReplacement = $1 }
deletedTypist.onWithheldInput = { savedKeys += $0 }
deletedTypist.replaceLastWord(expected: "ghbdtn", with: "привет", ticket: deletedTicket,
 separator: enter, separatorCharacter: "\n", navigates: true) { result in
    require(result == .uncertain, "deletion without replacement is uncertain"); deletedDone = true
}
drain(deletedTypist, done: { deletedDone })
require(deleted.editor.string == "before  after" && deleted.writes == 1, "deletion failure never blindly restores or retries")
require(savedOriginal == "ghbdtn" && savedReplacement == "привет", "deletion retains exact original and planned replacement")
require(deletedSent == 0 && savedKeys == "⏎", "deletion never submits queued Enter")
print("PASS: deletion-only keeps original, planned replacement and withheld Enter")

let (deletedUnicode, deletedUnicodeTarget) = fixture()
deletedUnicode.direct = false; deletedUnicode.deletionOnly = true
require(replace(deletedUnicodeTarget) == .uncertain && deletedUnicode.posts == 1 && deletedUnicode.realUnicodeEvents == 2,
        "editor consuming production Unicode pair without insertion is uncertain and never retried")
require(deletedUnicode.editor.string == "before  after", "no blind restoration after consumed Unicode pair")
print("PASS: deletion-only after real production Unicode pair remains uncertain")

let (deletedSelection, deletedSelectionTarget) = fixture()
deletedSelection.deletionOnly = true
deletedSelection.editor.setSelectedRange(NSRange(location: 7, length: 6))
var selectionDone = false; var selectionOriginal = ""; var selectionPlanned = ""
let selectionTypist = Typist(postEvent: { _ in fatalError("selection must never send a key") })
selectionTypist.onUnconfirmedReplacement = { selectionOriginal = $0; selectionPlanned = $1 }
SelectionConverter().replace(.init(target: deletedSelectionTarget, range: CFRange(location: 7, length: 6),
 text: "ghbdtn", originalSelection: CFRange(location: 7, length: 6)), permit: .init(), typist: selectionTypist,
 replayRoute: .init(target: deletedSelectionTarget)) { result, _ in
    require(result == .uncertain, "selected-text deletion uncertain"); selectionDone = true
}
drain(selectionTypist, done: { selectionDone })
require(selectionOriginal == "ghbdtn" && selectionPlanned == "привет", "explicit Option selection retains both full texts")
print("PASS: production SelectionConverter retains source and converted text")

let dictationDeletion = FixtureAX()
dictationDeletion.deletionOnly = true
let speechPermit = DictationInsertionPermit()
guard case .target(let dictationDestination) = dictationDeletion.capture(speechPermit) else { fatalError("speech capture") }
var speechDone = false; var speechOriginal = ""; var speechPlanned = ""
let speechTypist = Typist(postEvent: { _ in fatalError("speech queue must not replay a key") })
speechTypist.onUnconfirmedReplacement = { speechOriginal = $0; speechPlanned = $1 }
speechTypist.insertDictation("новый текст", target: dictationDestination, permit: speechPermit) { result in
    require(result == .fallback(.unconfirmed), "dictation replacing selection with deletion falls back"); speechDone = true
}
drain(speechTypist, done: { speechDone })
require(speechOriginal == "старый" && speechPlanned == "новый текст", "dictation deletion retains selected original and complete recognition")
print("PASS: shared dictation queue retains selected source after unconfirmed write")

let focus = InputFocusGuard()
let core = EngineCore(detector: Detector(), snippets: SnippetStore())
var changes = 0
focus.onChange = { changes += 1; _ = core.handle(.reset) }
for ch in "ghbdtn" { _ = core.handle(.char(ch)) }
let (_, boundTarget) = fixture()
let first = focus.bind(boundTarget, generation: focus.generation)!
require(changes == 0 && core.handle(.boundary(" ")).expectedText == "ghbdtn", "initial production bind preserves first buffered word")
first.replayRoute.didBecomeUncertain()
focus.finishBatch()
require(focus.ticket == nil && !first.permit.isAllowed, "uncertain route expires when queued batch ends")
let second = focus.bind(boundTarget, generation: focus.generation)!
require(second.replayRoute.canReplay(permit: second.permit, navigates: true), "fresh Enter is not blocked by old uncertainty")
print("PASS: cold bind preserves core, idle uncertainty cannot suppress fresh Enter")
