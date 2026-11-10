import AppKit
import WebKit
import SwitcherCore

enum EventTap { static let syntheticMarker: Int64 = 0xC0FFEE }
func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
func fixtureProcessBundleURL(pid: pid_t) -> URL? {
    require(pid == getpid(), "process lookup is limited to own fixture")
    return URL(fileURLWithPath: ProcessInfo.processInfo.environment["MLS_WEBKIT_TEST_BUNDLE"]!)
}
func main<T>(_ body: () -> T) -> T { Thread.isMainThread ? body() : DispatchQueue.main.sync(execute: body) }
func pump(_ seconds: Double = 0.03) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }

// Production Unicode eligibility reads these two raw AX RPCs against the real
// in-process WebCore wrapper. No role/capability predicate is copied here.
var eligibilityTarget: WebKitAX?
func fixtureAXUIElementCopyAttributeValue(_ element: AXUIElement, _ name: CFString,
                                         _ value: UnsafeMutablePointer<CFTypeRef?>) -> AXError {
    guard let target = eligibilityTarget, CFEqual(element, target.element) else { fatalError("eligibility RPC outside owned WebKit target") }
    value.pointee = target.attribute(name as String, of: element)
    return value.pointee == nil ? .noValue : .success
}
func fixtureAXUIElementIsAttributeSettable(_ element: AXUIElement, _ name: CFString,
                                         _ settable: UnsafeMutablePointer<DarwinBoolean>) -> AXError {
    guard let target = eligibilityTarget, CFEqual(element, target.element) else { fatalError("capability RPC outside owned WebKit target") }
    settable.pointee = DarwinBoolean(target.node.accessibilityIsAttributeSettable(NSAccessibility.Attribute(rawValue: name as String)))
    return .success
}

// WebKit1 exposes the system WebCore accessibility wrapper in this process.
// WKWebView's remote AX tree requires cross-process AX permission; this fixture
// deliberately uses neither that permission nor another application's AX tree.
final class WebKitAX: DictationAccessibility {
    let web = WebView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
    let window: NSWindow
    var node: NSObject!
    let element = AXUIElementCreateApplication(getpid())
    var isTrusted = true
    var isSecure = false
    var focused = true
    var forceDirect = false
    var ignoreUnicode = false
    var afterSelection: (() -> Void)?
    var afterPost: (() -> Void)?
    var directWrites = 0
    var unicodePosts = 0
    let kind: String

    init(kind: String = "input") {
        self.kind = kind
        window = NSWindow(contentRect: web.frame, styleMask: [], backing: .buffered, defer: false)
        window.contentView = web
        let markup: String
        switch kind {
        case "textarea": markup = "<textarea id='name'></textarea>"
        case "contenteditable": markup = "<div id='name' contenteditable='true' role='textbox' aria-multiline='true'></div>"
        case "palette": markup = "<input id='name' type='search' role='combobox' aria-expanded='false' aria-controls='options'><div id='options' role='listbox'></div>"
        default: markup = "<input id='name' autocomplete='name'>"
        }
        web.mainFrame.loadHTMLString("""
            \(markup)<script>
            window.inputs=[]; const field=document.getElementById('name');
            field.addEventListener('input', e => inputs.push({value:field.value, type:e.inputType}));
            function fieldValue() { return field.isContentEditable ? field.textContent : field.value; }
            function fieldSelection() {
              if (!field.isContentEditable) return [field.selectionStart,field.selectionEnd];
              const s=getSelection(), r=s.getRangeAt(0), prefix=document.createRange();
              prefix.selectNodeContents(field); prefix.setEnd(r.startContainer,r.startOffset);
              const start=prefix.toString().length; return [start,start+r.toString().length];
            }
            function seedField(value,start,end) {
              if (field.isContentEditable) {
                field.textContent=value; field.focus(); const r=document.createRange();
                r.setStart(field.firstChild,start); r.setEnd(field.firstChild,end);
                const s=getSelection(); s.removeAllRanges(); s.addRange(r);
              } else { field.value=value; field.focus(); field.setSelectionRange(start,end); }
              inputs=[];
            }
            </script>
            """, baseURL: nil)
        let deadline = Date().addingTimeInterval(4)
        while web.stringByEvaluatingJavaScript(from: "typeof field") != "object", Date() < deadline { pump() }
        func visit(_ object: NSObject, depth: Int = 0) {
            guard depth < 12 else { return }
            if let role = object.accessibilityAttributeValue(.role) as? String,
               [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role) { node = object; return }
            for child in object.accessibilityAttributeValue(.children) as? [NSObject] ?? [] { visit(child, depth: depth + 1) }
        }
        visit(web)
        require(node != nil, "own WebKit \(kind) AX text field exists")
    }
    func seed(_ value: String, selection: NSRange) {
        let data = try! JSONSerialization.data(withJSONObject: [value])
        let encoded = String(data: data, encoding: .utf8)!
        _ = web.stringByEvaluatingJavaScript(from: "seedField(\(encoded)[0],\(selection.location),\(selection.location + selection.length))")
        pump()
        require(domValue == value && domSelection == selection, "literal source and caret before conversion")
    }
    var domValue: String { web.stringByEvaluatingJavaScript(from: "fieldValue()")! }
    var domSelection: NSRange {
        let start = Int(web.stringByEvaluatingJavaScript(from: "String(fieldSelection()[0])")!)!
        let end = Int(web.stringByEvaluatingJavaScript(from: "String(fieldSelection()[1])")!)!
        return NSRange(location: start, length: end - start)
    }
    var domInputCount: Int { Int(web.stringByEvaluatingJavaScript(from: "String(inputs.length)")!)! }
    func focusedElement(pid: pid_t) -> AXUIElement? { focused ? element : nil }
    func enableAccessibility(pid: pid_t) { }
    func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        main {
            if name == kAXSelectedTextRangeAttribute {
                guard let value = node.accessibilityAttributeValue(.selectedTextRange) as? NSValue else { return nil }
                var range = CFRange(location: value.rangeValue.location, length: value.rangeValue.length)
                return AXValueCreate(.cfRange, &range)
            }
            return node.accessibilityAttributeValue(NSAccessibility.Attribute(rawValue: name)) as CFTypeRef?
        }
    }
    func selectedTextIsSettable(_ element: AXUIElement) -> Bool { main { node.accessibilityIsAttributeSettable(.selectedText) } }
    func supportsUnicodeInsertion(_ element: AXUIElement) -> Bool {
        main {
            precondition(eligibilityTarget == nil)
            eligibilityTarget = self
            defer { eligibilityTarget = nil }
            return SystemDictationAccessibility().supportsUnicodeInsertion(element)
        }
    }
    func prefersUnicodeInsertion(pid: pid_t) -> Bool { !forceDirect && SystemDictationAccessibility().prefersUnicodeInsertion(pid: pid) }
    func setSelection(_ range: CFRange, in element: AXUIElement) -> Bool {
        main { node.accessibilitySetValue(NSValue(range: NSRange(location: range.location, length: range.length)), forAttribute: .selectedTextRange) }
        afterSelection?()
        return true // The void in-process wrapper acknowledges dispatch, not completion.
    }
    func setSelectedText(_ text: String, in element: AXUIElement) -> AXError {
        directWrites += 1
        main { node.accessibilitySetValue(text, forAttribute: .selectedText) }
        return .success
    }
    func postUnicode(_ text: String, pid: pid_t) -> Bool {
        unicodePosts += 1
        let transport = SystemDictationAccessibility(postEvent: { event, destination in
            require(destination == getpid(), "Unicode only addresses own process")
            require(event.getIntegerValueField(.eventSourceUserData) == EventTap.syntheticMarker, "production synthetic marker")
            if !self.ignoreUnicode {
                main {
                    let received = CGEvent(withDataAllocator: nil, data: event.data!)!
                    let native = NSEvent(cgEvent: received)!
                    if received.type == .keyDown { self.web.mainFrame.frameView.documentView.keyDown(with: native) }
                    else { self.web.mainFrame.frameView.documentView.keyUp(with: native) }
                }
            }
        })
        let result = transport.postUnicode(text, pid: pid)
        afterPost?()
        return result
    }
    // Observation registration is injected; concurrent notification behavior has
    // separate G23 coverage. All WebCore attributes and input below are real.
    func observe(_ element: AXUIElement, pid: pid_t, changed: @escaping (DictationAXChange) -> Void) -> AnyObject? { NSObject() }
    var target: InputFocusGuard.Target { .init(element: element, pid: getpid(), accessibility: self) }
    var ticket: InputFocusGuard.Ticket { .init(target: target, permit: .init(), replacementPermit: .init(), replayRoute: .init(target: target)) }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
func drain(_ typist: Typist, _ done: @escaping () -> Bool) {
    let deadline = Date().addingTimeInterval(5)
    while (!done() || typist.isBusy) && Date() < deadline { pump(0.005) }
    pump()
    require(done() && !typist.isBusy, "production queue completes")
}

// Establish the real platform defect independently from the proposed routing:
// capability and range are implemented, but selected-text mutation is a no-op.
let broken = WebKitAX()
broken.seed("шднф", selection: NSRange(location: 4, length: 0))
broken.forceDirect = true
require(broken.selectedTextIsSettable(broken.element), "WebKit advertises selected-text setter")
require(broken.supportsUnicodeInsertion(broken.element), "WebKit advertises native selection/value capabilities")
var brokenResult: InputFocusGuard.ReplacementResult?
let brokenTypist = Typist(postEvent: { _ in fatalError("no separator in direct probe") })
brokenTypist.replaceLastWord(expected: "шднф", with: "ilya", ticket: broken.ticket, separator: nil, separatorCharacter: nil, navigates: false) { brokenResult = $0 }
drain(brokenTypist, { brokenResult != nil })
require(brokenResult == .uncertain && broken.domValue == "шднф" && broken.domInputCount == 0 && broken.directWrites == 1 && broken.unicodePosts == 0,
        "real WebKit direct setter leaves source untouched; no retry")
require(broken.domSelection == NSRange(location: 4, length: 0), "failed direct write restores verified caret")
print("PASS: real WebKit AXSelectedText capability is true but setter does not insert")

let automatic = WebKitAX()
automatic.seed("шднф", selection: NSRange(location: 4, length: 0))
var autoResult: InputFocusGuard.ReplacementResult?
let autoTypist = Typist(postEvent: { _ in fatalError("successful Space is inline") })
autoTypist.replaceLastWord(expected: "шднф", with: "ilya", ticket: automatic.ticket,
    separator: Typist.makeKeyPress(keyCode: 49, flags: [])!, separatorCharacter: " ", navigates: false) { autoResult = $0 }
drain(autoTypist, { autoResult != nil })
require(automatic.domValue == "ilya " && automatic.domSelection == NSRange(location: 5, length: 0) && autoResult == .confirmed,
        "Safari route must replace шднф with literal ilya-space once; actual=\(automatic.domValue), result=\(String(describing: autoResult))")
require(automatic.domInputCount == 1 && automatic.directWrites == 0 && automatic.unicodePosts == 1, "replacement is one native edit, no attempted direct write")
print("PASS: automatic Space reaches real WebKit text input once with correct caret")

for (label, key, flags) in [("Enter", CGKeyCode(36), CGEventFlags()),
                           ("ShiftEnter", 36, CGEventFlags.maskShift),
                           ("Tab", 48, CGEventFlags())] {
    let ax = WebKitAX()
    ax.seed("пфьуищн", selection: NSRange(location: 7, length: 0))
    var result: InputFocusGuard.ReplacementResult?
    var separators: [CGEvent] = []
    let typist = Typist(postEvent: { event in
        main {
            require(ax.domValue == "gameboy" && ax.domSelection == NSRange(location: 7, length: 0), "\(label) delivered only after complete replacement")
            separators.append(CGEvent(withDataAllocator: nil, data: event.data!)!)
        }
    })
    typist.replaceLastWord(expected: "пфьуищн", with: "gameboy", ticket: ax.ticket,
        separator: Typist.makeKeyPress(keyCode: key, flags: flags)!, separatorCharacter: key == 48 ? "\t" : "\n", navigates: true) { result = $0 }
    drain(typist, { result != nil })
    require(result == .confirmed && ax.domInputCount == 1 && separators.count == 2, "\(label) once after verified WebKit input")
    require(separators[0].type == .keyDown && separators[1].type == .keyUp
        && separators.allSatisfy { $0.getIntegerValueField(.keyboardEventKeycode) == key && $0.flags == flags }, "\(label) native keycode, modifiers and pair retained")
}
print("PASS: gameboy replacement precedes Enter/ShiftEnter/Tab with native pair and flags")

for selected in [false, true] {
    let ax = WebKitAX()
    let initial = NSRange(location: selected ? 3 : 7, length: selected ? 4 : 0)
    ax.seed("🙂 шднф tail", selection: initial)
    let selection = SelectionConverter.Selection(target: ax.target, range: CFRange(location: 3, length: 4), text: "шднф",
        originalSelection: CFRange(location: initial.location, length: initial.length), isWord: !selected)
    var result: InputFocusGuard.ReplacementResult?
    let ticket = ax.ticket
    let typist = Typist(postEvent: { event in
        main {
            let native = NSEvent(cgEvent: CGEvent(withDataAllocator: nil, data: event.data!)!)!
            if event.type == .keyDown { ax.web.mainFrame.frameView.documentView.keyDown(with: native) }
            else { ax.web.mainFrame.frameView.documentView.keyUp(with: native) }
        }
    })
    SelectionConverter().replace(selection, permit: .init(), typist: typist, replayRoute: ticket.replayRoute) { value, language in
        require(language == .en, "Option conversion chooses EN"); result = value
    }
    typist.send(Typist.makeUnicodePress("x")!, ticket: ticket)
    drain(typist, { result != nil })
    require(result == .confirmed && ax.domValue == "🙂 ilyax tail" && ax.domSelection == NSRange(location: 8, length: 0), "Option selected/word conversion preserves UTF16 prefix, tail and queued character")
    require(ax.domInputCount == 2 && ax.directWrites == 0 && ax.unicodePosts == 1, "Option replacement and queued input each delivered once")
}
print("PASS: Option word/selected conversion preserves emoji/context and rapid input")

let cancelled = WebKitAX()
cancelled.seed("шднф", selection: NSRange(location: 4, length: 0))
let cancelledTicket = cancelled.ticket
cancelled.afterSelection = { cancelledTicket.replacementPermit.cancel() }
var cancelledResult: InputFocusGuard.ReplacementResult?
let cancelledTypist = Typist(postEvent: { _ in fatalError("cancelled selection may not replay input") })
cancelledTypist.replaceLastWord(expected: "шднф", with: "ilya", ticket: cancelledTicket, separator: nil, separatorCharacter: nil, navigates: false) { cancelledResult = $0 }
drain(cancelledTypist, { cancelledResult != nil })
require(cancelledResult != .confirmed && cancelled.domValue == "шднф" && cancelled.domInputCount == 0
    && cancelled.directWrites == 0 && cancelled.unicodePosts == 0, "cancellation after WebKit selection dispatch never writes text")

for changedFocus in [false, true] {
    let ax = WebKitAX()
    ax.seed(changedFocus ? "шднф" : "xшднф", selection: NSRange(location: changedFocus ? 4 : 5, length: 0))
    ax.focused = !changedFocus
    var result: InputFocusGuard.ReplacementResult?
    let typist = Typist(postEvent: { _ in fatalError("no separator") })
    typist.replaceLastWord(expected: "шднф", with: "ilya", ticket: ax.ticket, separator: nil, separatorCharacter: nil, navigates: false) { result = $0 }
    drain(typist, { result != nil })
    require(result == .untouched && ax.domInputCount == 0 && ax.directWrites == 0 && ax.unicodePosts == 0, "stale prefix or changed focus prevents text mutation")
}
print("PASS: pending selection cancellation, stale source boundary and focus guards")

for partial in [false, true] {
    let ax = WebKitAX()
    ax.seed("шднф", selection: NSRange(location: 4, length: 0))
    let ticket = ax.ticket
    if partial { ax.afterPost = { ticket.replacementPermit.cancel() } }
    else { ax.ignoreUnicode = true }
    var result: InputFocusGuard.ReplacementResult?
    var original = "", planned = "", held = ""
    let typist = Typist(postEvent: { _ in fatalError("unconfirmed input must not submit Enter") })
    typist.onUnconfirmedReplacement = { original = $0; planned = $1 }
    typist.onWithheldInput = { held += $0 }
    typist.replaceLastWord(expected: "шднф", with: "abcdefghijklmnopQRST", ticket: ticket,
        separator: Typist.makeKeyPress(keyCode: 36, flags: [])!, separatorCharacter: "\n", navigates: true) { result = $0 }
    drain(typist, { result != nil })
    require(result == .uncertain && ax.domValue == (partial ? "abcdefghijklmnop" : "шднф"), "uncertain/no-op Unicode never blind-retries or restores source")
    require(original == "шднф" && planned == "abcdefghijklmnopQRST" && held == "⏎", "entire original, intended text and Enter remain recoverable")
    require(ax.unicodePosts == 1 && ax.directWrites == 0, "no fallback to setter after attempted native insertion")
}
print("PASS: no-op/partial Unicode preserves recovery, withholds Enter and never retries")
let readonly = WebKitAX()
readonly.seed("шднф", selection: NSRange(location: 4, length: 0))
_ = readonly.web.stringByEvaluatingJavaScript(from: "field.readOnly=true")
pump()
var readonlyResult: InputFocusGuard.ReplacementResult?
let readonlyTypist = Typist(postEvent: { _ in fatalError("no readonly separator") })
readonlyTypist.replaceLastWord(expected: "шднф", with: "ilya", ticket: readonly.ticket, separator: nil, separatorCharacter: nil, navigates: false) { readonlyResult = $0 }
drain(readonlyTypist, { readonlyResult != nil })
require(readonlyResult == .untouched && readonly.domValue == "шднф" && readonly.unicodePosts == 0 && readonly.directWrites == 0,
    "readonly WebKit field refuses native route without mutation")
print("PASS: readonly WebKit control cannot authorize native insertion")

let speech = WebKitAX()
speech.seed("До шднф после", selection: NSRange(location: 3, length: 4))
let speechPermit = DictationInsertionPermit()
guard case .target(let speechTarget) = DictationTarget.capture(expectedPID: getpid(), permit: speechPermit, accessibility: speech) else { fatalError("own WebKit speech target capture") }
var speechResult: DictationInsertionResult?
let speechTypist = Typist(postEvent: { _ in fatalError("dictation does not submit keys") })
speechTypist.insertDictation("новый полный текст", target: speechTarget, permit: speechPermit) { speechResult = $0 }
drain(speechTypist, { speechResult != nil })
require(speechResult == .inserted && speech.domValue == "До новый полный текст после" && speech.domSelection == NSRange(location: 21, length: 0),
    "shared dictation route inserts full text and preserves surroundings")
require(speech.directWrites == 0 && speech.unicodePosts == 2 && speech.domInputCount == 2, "shared dictation chunks are once-only native edits")
print("PASS: shared Safari dictation route preserves source surroundings and full chunked text")
for kind in ["input", "textarea", "contenteditable", "palette"] {
    for selected in [true, false] {
        let ax = WebKitAX(kind: kind)
        let initial = NSRange(location: selected ? 3 : 7, length: selected ? 4 : 0)
        ax.seed("🙂 кмсф tail", selection: initial)
        let role = ax.node.accessibilityAttributeValue(.role) as? String ?? "missing"
        let supported = ax.supportsUnicodeInsertion(ax.element)
        let selection = SelectionConverter.Selection(target: ax.target, range: CFRange(location: 3, length: 4), text: "кмсф",
            originalSelection: CFRange(location: initial.location, length: initial.length), isWord: !selected,
            sourceValue: "🙂 кмсф tail")
        var result: InputFocusGuard.ReplacementResult?
        let typist = Typist(postEvent: { _ in fatalError("manual conversion never submits") })
        SelectionConverter().replace(selection, permit: .init(), typist: typist, replayRoute: ax.ticket.replayRoute) { result = $0; _ = $1 }
        drain(typist, { result != nil })
        print("WebKit \(kind) role=\(role), supported=\(supported), selected=\(selected), result=\(String(describing: result)), text=\(ax.domValue), caret=\(ax.domSelection), unicodePosts=\(ax.unicodePosts), directWrites=\(ax.directWrites)")
        require(result == .confirmed && ax.domValue == "🙂 rvca tail" && ax.domSelection == NSRange(location: 7, length: 0),
                "real WebKit \(kind) \(selected ? "selection" : "word") preserves emoji, suffix and caret")
        require(ax.domInputCount == 1 && ax.unicodePosts == 1 && ax.directWrites == 0,
                "real WebKit \(kind) uses one verified native insertion without setter retry")
        print("PASS: real WebKit \(kind) role=\(role) \(selected ? "selected" : "preexisting") кмсф→rvca; production eligibility; exact DOM/caret")
    }
}
print("WebKit harness passed: actual system WebCore AX wrapper and local text input; not Safari/WindowServer delivery.")
