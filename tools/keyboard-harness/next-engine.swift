import AppKit
import ApplicationServices
import SwitcherCore
func require(_ condition: @autoclosure () -> Bool, _ message: String) {
 guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
func mainValue<T>(_ block: () -> T) -> T {
 if Thread.isMainThread { return block() }
 return DispatchQueue.main.sync(execute: block)
}
final class FixtureAX: DictationAccessibility {
 let editors = [NSTextView(), NSTextView()]
 let elements = [AXUIElementCreateApplication(harnessPID), AXUIElementCreateApplication(harnessPID + 1)]
 var activeField = 0
 var editor: NSTextView { editors[activeField] }
 var element: AXUIElement { elements[activeField] }
 func view(for element: AXUIElement) -> NSTextView {
  editors[CFEqual(element, elements[0]) ? 0 : 1]
 }
 let unicode: Bool
 var isTrusted = true
 var isSecure = false
 var chromium = false
 var physicalModifiers: CGEventFlags = []
 var postHook: ((CGEvent) -> Void)?
 var boundarySnapshots: [(UInt16, String, CGEventFlags)] = []
 var unavailableField = false
 var unavailableSelection = false
 var unavailableText = false
 var secureField = false
 var needsBootstrap = false
 var bootstrapWrapper = false
 let wrapper = AXUIElementCreateApplication(harnessPID + 2)
 var selectionReadHook: (() -> Void)?
 var valueReadsBeforeHook = 0
 var valueReadHook: (() -> Void)?
 var bootstrapHook: (() -> Void)?
 var selectionHook: (() -> Void)?
 var ignoreWrites = false
 var suppressedUpsValid = true
 var syntheticFilter: ((CGEvent) -> TapDecision)?
 var posted: [(CGEventType, UInt16, CGEventFlags)] = []
 init(unicode: Bool) { self.unicode = unicode }
 func focusedElement(pid: pid_t) -> AXUIElement? {
  mainValue {
   guard pid == harnessPID && harnessFrontPID == pid && !unavailableField else { return nil }
   return needsBootstrap ? (bootstrapWrapper ? wrapper : nil) : element
  }
 }
 func enableAccessibility(pid: pid_t) { mainValue { needsBootstrap=false; if let hook=bootstrapHook { bootstrapHook=nil; hook() } } }
 func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
  mainValue {
   if CFEqual(element,wrapper) { return name == kAXRoleAttribute ? kAXGroupRole as CFString : nil }
   switch name {
   case kAXValueAttribute:
    if unavailableText { return nil }
    let value=view(for: element).string as CFString
    if let hook=valueReadHook {
     if valueReadsBeforeHook > 0 { valueReadsBeforeHook -= 1 }
     else { valueReadHook=nil; hook() }
    }
    return value
   case kAXSelectedTextRangeAttribute:
    if unavailableSelection { return nil }
    let ns=view(for: element).selectedRange(); var range=CFRange(location:ns.location,length:ns.length)
    if let hook=selectionReadHook { selectionReadHook=nil; hook() }
    return AXValueCreate(.cfRange,&range)
   case kAXSubroleAttribute: return secureField ? kAXSecureTextFieldSubrole as CFString : nil
   case kAXRoleAttribute: return kAXTextAreaRole as CFString
   default: return nil
   }
  }
 }
 func selectedTextIsSettable(_ element: AXUIElement) -> Bool { true }
 func supportsUnicodeInsertion(_ element: AXUIElement) -> Bool { true }
 func prefersUnicodeInsertion(pid: pid_t) -> Bool { unicode }
 func setSelectedText(_ text: String, in element: AXUIElement) -> AXError {
  if !ignoreWrites { mainValue { view(for: element).setAccessibilitySelectedText(text) } }; return .success
 }
 func postUnicode(_ text: String, pid: pid_t) -> Bool {
  SystemDictationAccessibility(postEvent: { event, _ in if !self.ignoreWrites { self.receive(event) } }).postUnicode(text,pid:pid)
 }
 func setSelection(_ range: CFRange, in element: AXUIElement) -> Bool {
  mainValue {
   view(for: element).setSelectedRange(NSRange(location:range.location,length:range.length))
   if range.length > 0, let hook=selectionHook { selectionHook=nil; hook() }
  }; return true
 }
 func observe(_ element: AXUIElement,pid:pid_t,changed:@escaping (DictationAXChange)->Void) -> AnyObject? { NSObject() }
 func receive(_ event: CGEvent, resolvingPhysicalKey: Bool = false) {
  mainValue {
   guard let data=event.data,let received=CGEvent(withDataAllocator:nil,data:data) else { fatalError("CG serialization") }
   let code=UInt16(truncatingIfNeeded:event.getIntegerValueField(.keyboardEventKeycode))
   if event.getIntegerValueField(.eventSourceUserData)==EventTap.syntheticMarker {
    require(syntheticFilter?(event) == .pass,"own synthetic down/up bypasses EventTap state machine")
   }
   if resolvingPhysicalKey {
    posted.append((event.type,code,event.flags))
    if let hook=postHook { hook(event) }
    if event.type == .keyDown && [36,48,49].contains(code) { boundarySnapshots.append((code, editor.string, event.flags)) }
   }
   let native: NSEvent
   if resolvingPhysicalKey && code != 0 {
    // WindowServer is absent from this local receiver. Resolve native physical
    // key identity/flags here, preserving the recorded original posted event.
    let code=UInt16(truncatingIfNeeded:received.getIntegerValueField(.keyboardEventKeycode))
    guard let resolved=NSEvent.keyEvent(with:received.type == .keyDown ? .keyDown : .keyUp,
     location:.zero,modifierFlags:NSEvent.ModifierFlags(rawValue:UInt(received.flags.rawValue)),
     timestamp:0,windowNumber:0,context:nil,
     characters:KeyTranslator.characters(keyCode:code,flags:received.flags),
     charactersIgnoringModifiers:KeyTranslator.characters(keyCode:code,flags:[]),
     isARepeat:received.getIntegerValueField(.keyboardEventAutorepeat) != 0,keyCode:code) else { fatalError("native key resolution") }
    native=resolved
   } else {
    // Unicode retains production event creation, payload and CG roundtrip.
    guard let event=NSEvent(cgEvent:received) else { fatalError("NSEvent Unicode interpretation") }; native=event
   }
   if received.type == .keyDown { editor.keyDown(with:native) }
   if received.type == .keyUp { editor.keyUp(with:native) }
  }
 }

}
let app=NSApplication.shared
app.setActivationPolicy(.prohibited)
func drain(_ duration: Double = 0.35) { RunLoop.current.run(until:Date().addingTimeInterval(duration)) }
func awaitFixture(_ message: String, condition: () -> Bool) {
 let deadline=Date().addingTimeInterval(3)
 while !condition() && Date() < deadline { drain(0.005) }
 require(condition(), message)
}

func fixture(unicode:Bool, snippets: String? = nil, chromium: Bool = false, configure: (inout AppConfig) -> Void = { _ in }) -> Engine {
 harnessFrontPID=harnessPID
 currentFixture=FixtureAX(unicode:unicode)
 currentFixture.unavailableField=true
 currentFixture.chromium=chromium
 currentFixture.editor.string=""; currentFixture.editor.setSelectedRange(NSRange(location:0,length:0))
 let directory=URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
 let config=Config(directory:directory); config.update { $0.excludedApps=[]; $0.sounds=false; configure(&$0) }
 if let snippets { try! snippets.write(to:config.snippetsURL,atomically:true,encoding:.utf8) }
 let engine=Engine(config:config); require(engine.start(),"inert registration starts")
 currentFixture.syntheticFilter = { [weak engine] in engine?.probeEvent($0) ?? .pass }
 let event=CGEvent(keyboardEventSource:CGEventSource(stateID:.privateState),virtualKey:58,keyDown:false)!
 event.type = .flagsChanged; event.flags=[]; _=engine.probeEvent(event)
 drain(0.15)
 require(!engine.probeFocusReady,"fixture has no AX target")
 return engine
}
func physical(_ engine:Engine, code:UInt16, autorepeat:Bool=false, flags:CGEventFlags=[], deliver:Bool=true) -> TapDecision {
 let source=CGEventSource(stateID:.privateState)
 let down=CGEvent(keyboardEventSource:source,virtualKey:CGKeyCode(code),keyDown:true)!
 down.flags=flags; down.setIntegerValueField(.keyboardEventAutorepeat,value:autorepeat ? 1 : 0)
 let characters=KeyTranslator.characters(keyCode:code,flags:flags); let utf16=Array(characters.utf16)
 utf16.withUnsafeBufferPointer { down.keyboardSetUnicodeString(stringLength:$0.count,unicodeString:$0.baseAddress) }
 let decision=engine.probeEvent(down)
 if decision == .pass && deliver { currentFixture.receive(down) }
 let up=CGEvent(keyboardEventSource:source,virtualKey:CGKeyCode(code),keyDown:false)!
 up.flags=flags; let upDecision=engine.probeEvent(up)
 if decision == .suppress && upDecision != .suppress { currentFixture.suppressedUpsValid = false }
 if decision == .pass { require(upDecision == .pass,"passed physical key must not lose its key-up to stale ownership") }
 if upDecision == .pass && deliver { currentFixture.receive(up) }
 return decision
}
// Translate through the captured real input-source data without changing the
// OS layout. Verify private source text before every separator, even while the
// user independently changes their active input source during this long run.
print("Frozen TIS fixture: " + harnessKeyboardSnapshotDescription())
KeyTranslator.start()
let g=KeyTranslator.characters(keyCode:5,flags:[])
require(g=="g" || g=="п","harness requires an enabled RU/EN keyboard source")
let startsEnglish=g=="g"
let codes:[UInt16]=startsEnglish ? [5,4,11,2,17,45] : [4,14,37,37,31]
let original=startsEnglish ? "ghbdtn" : "руддщ"
let converted=startsEnglish ? "привет" : "hello"
func typeSource(_ engine:Engine) {
 var observed:[String]=[]
 for code in codes {
  observed.append(KeyTranslator.characters(keyCode:code,flags:[]))
  require(physical(engine,code:code) == .pass,"source key passes before correction")
 }
 if currentFixture.editor.string != original {
  fputs("Source diagnostic: startupKey5=\(String(reflecting:g)); expected=\(String(reflecting:original)); observedPerKey=\(observed); actual=\(String(reflecting:currentFixture.editor.string)); currentKey5=\(String(reflecting:KeyTranslator.characters(keyCode:5,flags:[])))\n",stderr)
 }
 require(currentFixture.editor.string==original,"literal wrong-layout source verified BEFORE separator")
}
func postedKeys(_ codes:[UInt16],flags:CGEventFlags=[]) {
 require(currentFixture.suppressedUpsValid,"all suppressed physical downs own their keyUps, including original separator")
 let events=currentFixture.posted
 require(events.count==codes.count*2,"complete posted down/up pairs")
 for (i,code) in codes.enumerated() {
  require(events[i*2].0 == .keyDown && events[i*2+1].0 == .keyUp,"posted native order down/up")
  require(events[i*2].1==code && events[i*2+1].1==code,"posted original keycode")
  require(events[i*2].2==flags && events[i*2+1].2==flags,"posted original modifier flags")
 }
}
// Option's target may change programmatically between 100ms focus samples.
// The old field has a real buffered word, so stale core state must not win.
func option(_ engine: Engine) {
 for flags in [CGEventFlags.maskAlternate, CGEventFlags()] {
  let event=CGEvent(keyboardEventSource:CGEventSource(stateID:.privateState),virtualKey:58,keyDown:false)!
  event.type = .flagsChanged; event.flags=flags
  _=engine.probeEvent(event)
 }
}


if ProcessInfo.processInfo.environment["MLS_NEXT_REPAIR"] == "protected" {
 let e=fixture(unicode:false)
 currentFixture.unavailableField=false; currentFixture.secureField=true; drain(0.25)
 currentFixture.unavailableField=true; drain(0.25)
 let windows=Set(NSApplication.shared.windows.map(ObjectIdentifier.init))
 typeSource(e)
 require(physical(e,code:49) == .pass,"known protected field stays protected when AX becomes unavailable in same PID")
 drain(0.5)
 require(currentFixture.editor.string=="ghbdtn " && currentFixture.posted.isEmpty,"unknown AX cannot downgrade a known protected destination")
 let recovery=NSApplication.shared.windows.filter { !windows.contains(ObjectIdentifier($0)) }.flatMap { $0.contentView.map(viewText) ?? [] }.joined(separator:"\n")
 require(!recovery.contains("ghbdtn"),"protected input is never retained in recovery")
 currentFixture.unavailableField=false; currentFixture.secureField=false; drain(0.3)
 currentFixture.editor.string=""; currentFixture.editor.setSelectedRange(NSRange(location:0,length:0))
 let click=CGEvent(mouseEventSource:nil,mouseType:.leftMouseDown,mouseCursorPosition:.zero,mouseButton:.left)!
 _=e.probeEvent(click); typeSource(e)
 require(physical(e,code:49) == .suppress,"positively captured ordinary target clears protected state")
 drain(0.5)
 require(currentFixture.editor.string=="привет ","fresh correction resumes after positive nonprotected target")
 e.stop(); drain()
 let nextApp=fixture(unicode:false)
 currentFixture.unavailableField=false; currentFixture.secureField=true; drain(0.25)
 currentFixture.unavailableField=true; harnessFrontPID=harnessPID+1; drain(0.25)
 typeSource(nextApp)
 require(physical(nextApp,code:49) == .suppress,"positive PID change clears old application's protected field while AX remains absent")
 drain(0.5)
 require(currentFixture.editor.string=="привет ","new nil-AX application can correct its fresh word")
 nextApp.stop(); drain()
 print("PASS: protected-to-unknown stays private; ordinary target or new PID resumes"); exit(0)
}
if ProcessInfo.processInfo.environment["MLS_NEXT_REPAIR"] == "manual" {
 let e=fixture(unicode:false)
 for code:UInt16 in [4,14,37,37,31] { _=physical(e,code:code) }
 option(e); drain(0.5)
 require(currentFixture.editor.string=="руддщ","explicit Option choice precedes next character")
 // The fixture freezes ABC deliberately. Supply the translated character at
 // Engine's public input seam for this one cross-layout continuation, then
 // deliver the same real Unicode CGEvent into the owned native receiver.
 let stroke=KeyStroke(kind:.keyDown,keyCode:13,characters:"ц",flags:[],isAutorepeat:false)
 require(e.handle(keyEvent:stroke) == .pass,"manual continuation passes")
 let event=CGEvent(keyboardEventSource:nil,virtualKey:13,keyDown:true)!
 let units=Array("ц".utf16); units.withUnsafeBufferPointer { event.keyboardSetUnicodeString(stringLength:$0.count,unicodeString:$0.baseAddress) }
 currentFixture.receive(event)
 drain(0.5)
 require(currentFixture.editor.string=="руддщц","live does not reverse an explicit manual choice")
 e.stop(); drain(); print("PASS: explicit manual choice survives quiet-time continuation"); exit(0)
}
if ProcessInfo.processInfo.environment["MLS_NEXT_REPAIR"] == "snippet" {
 for prefix in [false,true] {
  let e=fixture(unicode:false,snippets:prefix ? #"{"ghbdtnX":"My custom snippet"}"# : #"{"ghbdtn":"My custom snippet"}"#)
  typeSource(e); drain(0.5)
  require(currentFixture.editor.string=="ghbdtn","live preserves registered snippet or its prefix")
  if prefix { _=physical(e,code:7,flags:.maskShift) }
  _=physical(e,code:49); drain(0.6)
  require(currentFixture.editor.string=="My custom snippet ","slow trigger expands exactly as fast trigger")
  e.stop(); drain()
 }
 print("PASS: quiet-time snippet and longer trigger prefix"); exit(0)
}
if ProcessInfo.processInfo.environment["MLS_NEXT_REPAIR"] == "caret" {
 require(!startsEnglish,"caret fixture requires pinned RussianWin")
 let e=fixture(unicode:false)
 currentFixture.editor.string="слово"; currentFixture.editor.setSelectedRange(NSRange(location:5,length:0))
 let changedApp=ProcessInfo.processInfo.environment["MLS_NEXT_CHANGED_APP"] == "1"
 if changedApp { harnessFrontPID=harnessPID+1 }
 let click=CGEvent(mouseEventSource:nil,mouseType:.leftMouseDown,mouseCursorPosition:.zero,mouseButton:.left)!
 _=e.probeEvent(click)
 if changedApp { drain(0.15) }
 _=physical(e,code:51); _=physical(e,code:32)
 require(currentFixture.editor.string=="словг","owned existing word edited before boundary")
 require(physical(e,code:49) == .pass,"post-caret-jump one-letter edit must stay unchanged")
 drain(0.5)
 require(currentFixture.editor.string=="словг ","boundary does not convert the inserted Cyrillic fragment to Latin")
 e.stop(); drain()
 let fresh=fixture(unicode:false)
 _=fresh.probeEvent(click); _=physical(fresh,code:49); _=physical(fresh,code:51)
 _=physical(fresh,code:32); _=physical(fresh,code:49); drain(0.5)
 require(currentFixture.editor.string=="u ","a completed boundary consumes the caret guard before the next edit")
 fresh.stop(); drain(); print("PASS: caret edit fragment and next-boundary reset"); exit(0)
}

let engine=fixture(unicode:false)
typeSource(engine)
require(physical(engine,code:49) == .suppress,"fresh separator held for replacement without AX")
drain(0.5)
require(currentFixture.editor.string=="привет ","fresh ghbdtn+Space with nil AX must become literal привет; actual=\(currentFixture.editor.string.debugDescription)")
engine.stop(); drain()
print("PASS: production Engine+EventTap+Typist, nil AX, owned NSTextView ghbdtn+Space")
let manual=fixture(unicode:false)
typeSource(manual); option(manual); drain(0.6)
require(currentFixture.editor.string=="привет","fresh ghbdtn+Option without AX must become привет; actual=\(currentFixture.editor.string.debugDescription)")
manual.stop(); drain()
print("PASS: fresh Option without AX")
let rapid=fixture(unicode:false)
typeSource(rapid)
require(physical(rapid,code:49) == .suppress,"Space correction starts")
for code:UInt16 in [0,11,8] { require(physical(rapid,code:code) == .suppress,"rapid input held behind replacement") }
drain(0.7)
require(currentFixture.editor.string=="привет abc","rapid physical text follows correction; actual=\(currentFixture.editor.string.debugDescription)")
require(currentFixture.suppressedUpsValid,"rapid suppressed down/up ownership")
rapid.stop(); drain()
print("PASS: rapid physical text ordered behind replacement without AX")
let live=fixture(unicode:false)
typeSource(live); drain(0.7)
require(currentFixture.editor.string=="привет","high-confidence quiet-time live correction without AX; actual=\(currentFixture.editor.string.debugDescription)")
live.stop(); drain()
print("PASS: quiet-time live correction without AX")

for (code,flags,separator) in [(UInt16(36),CGEventFlags(),"\n"),(UInt16(36),CGEventFlags.maskShift,"\n"),(UInt16(48),CGEventFlags(),"\t")] {
 let ordered=fixture(unicode:false); typeSource(ordered)
 currentFixture.physicalModifiers=flags
 require(physical(ordered,code:code,flags:flags) == .suppress,"navigation separator held before delivery")
 require(physical(ordered,code:code,autorepeat:true,flags:flags) == .suppress,"repeat navigation held behind correction")
 require(physical(ordered,code:0) == .suppress,"fast letter held behind navigation")
 currentFixture.physicalModifiers=[]
 drain(0.7)
 require(currentFixture.editor.string=="привет"+separator+separator+"a","ordered navigation/repeat/letter; actual=\(currentFixture.editor.string.debugDescription)")
 require(currentFixture.boundarySnapshots.first?.1=="привет","correction precedes first native navigation")
 require(currentFixture.boundarySnapshots.allSatisfy { $0.2==flags },"ShiftEnter keeps original flags")
 require(currentFixture.suppressedUpsValid,"navigation owns every suppressed keyUp")
 ordered.stop(); drain()
}
print("PASS: Enter/ShiftEnter/Tab, repeated navigation and fast next text")
for repeatCode:UInt16 in [5,51,49] {
 let repeating=fixture(unicode:false); typeSource(repeating)
 require(physical(repeating,code:49) == .suppress,"replacement starts before repeat")
 require(physical(repeating,code:repeatCode,autorepeat:true) == .suppress,"editing repeat serializes without AX")
 drain(0.6)
 let wanted=repeatCode==51 ? "привет" : repeatCode==49 ? "привет  " : "привет g"
 require(currentFixture.editor.string==wanted,"repeat follows complete replacement")
 repeating.stop(); drain()
}
print("PASS: printable, Backspace and Space repeats")
for mode in ["click","navigation","secure","recorder","tap","pid"] {
 let cancelled=fixture(unicode:false); typeSource(cancelled)
 currentFixture.physicalModifiers = .maskShift
 require(physical(cancelled,code:49) == .suppress,"queued correction before context invalidation")
 switch mode {
 case "click":
  let event=CGEvent(mouseEventSource:nil,mouseType:.leftMouseDown,mouseCursorPosition:.zero,mouseButton:.left)!
  _=cancelled.probeEvent(event)
 case "navigation": require(physical(cancelled,code:123,deliver:false) == .pass,"arrow passes and cancels")
 case "secure": currentFixture.isSecure=true
 case "recorder": cancelled.isRecordingHotkey=true
 case "tap": let event=CGEvent(source:nil)!; event.type = .tapDisabledByTimeout; _=cancelled.probeEvent(event)
 default: harnessFrontPID=harnessPID+1
 }
 drain(0.15); currentFixture.physicalModifiers=[]; drain(0.5)
 require(currentFixture.editor.string=="ghbdtn","\(mode) abort before deletion preserves source")
 require(currentFixture.posted.isEmpty,"\(mode) abort posts no destructive or separator events")
 if mode == "secure" {
  require(physical(cancelled,code:0) == .pass,"sensitive physical input passes instead of recovery buffering")
  require(currentFixture.editor.string=="ghbdtna","sensitive key reaches owned field once")
 }
 cancelled.stop(); drain()
}
print("PASS: abort before deletion for click/navigation/secure/recorder/tap/PID")
func viewText(_ view:NSView) -> [String] {
 (view as? NSTextView).map { [$0.string] } ?? view.subviews.flatMap(viewText)
}
let partial=fixture(unicode:false); typeSource(partial)
let windows=Set(NSApplication.shared.windows.map(ObjectIdentifier.init))
currentFixture.postHook={ event in
 if event.type == .keyDown && event.getIntegerValueField(.keyboardEventKeycode)==51 {
  currentFixture.postHook=nil
  let click=CGEvent(mouseEventSource:nil,mouseType:.leftMouseDown,mouseCursorPosition:.zero,mouseButton:.left)!
  _=partial.probeEvent(click)
 }
}
require(physical(partial,code:49) == .suppress,"partial replacement starts")
require(physical(partial,code:36) == .suppress,"Enter held before interrupted replacement")
drain(0.8)
require(currentFixture.editor.string=="ghbdt","one deletion applied, no blind second attempt")
require(currentFixture.posted.count==2,"posted down always releases even when cancelled")
let recovery=NSApplication.shared.windows.filter { !windows.contains(ObjectIdentifier($0)) }.flatMap { $0.contentView.map(viewText) ?? [] }.joined(separator:"\n")
require(recovery.contains("ghbdtn") && recovery.contains("привет") && recovery.contains("⏎"),"recovery preserves original, planned and held Enter")
drain(0.5)
require(currentFixture.posted.count==2,"interrupted mutation never retries")
partial.stop(); drain()
print("PASS: interrupted deletion retains recovery and never retries/submits Enter")
let chromium=fixture(unicode:false,chromium:true); typeSource(chromium); drain(0.45)
require(currentFixture.editor.string=="ghbdtn" && currentFixture.posted.isEmpty,"Chromium/Electron has no live mutation")
require(physical(chromium,code:49) == .suppress,"Chromium boundary remains available"); drain(0.5)
require(currentFixture.editor.string=="привет ","Chromium boundary correction")
chromium.stop(); drain()
let edited=fixture(unicode:false); typeSource(edited)
_=physical(edited,code:51); _=physical(edited,code:45); drain(0.45)
require(currentFixture.editor.string=="ghbdtn" && currentFixture.posted.isEmpty,"edited word does not live-correct")
_=physical(edited,code:49); drain(0.5)
require(currentFixture.editor.string=="привет ","edited word still corrects at boundary")
edited.stop(); drain()
print("PASS: Chromium and edited-word live gates")
let undo=fixture(unicode:false); typeSource(undo); _=physical(undo,code:49); drain(0.5)
option(undo); drain(0.5)
require(currentFixture.editor.string=="ghbdtn ","Option undoes posted automatic replacement without AX")
undo.stop(); drain()
let snippet=fixture(unicode:false,snippets:#"{"xx":"12345678901🙂🚀"}"#)
_=physical(snippet,code:7); _=physical(snippet,code:7); _=physical(snippet,code:49); drain(0.5)
require(currentFixture.editor.string=="12345678901🙂🚀 ","snippet UTF16 chunk boundary preserves surrogate pairs")
snippet.stop(); drain()
print("PASS: Option undo and emoji snippet chunks")
print("Next native Engine suite passed; final posting seam uses owned NSTextViews, not WindowServer/readback confirmation.")

let liveUndo=fixture(unicode:false); typeSource(liveUndo); drain(0.6)
option(liveUndo); drain(0.5)
require(currentFixture.editor.string=="ghbdtn","Option undoes live correction")
require(physical(liveUndo,code:49) == .pass,"undone live word is protected at next boundary")
drain(0.4)
require(currentFixture.editor.string=="ghbdtn ","live undo keeps literal original after Space")
liveUndo.stop(); drain()
print("PASS: live undo protects following Space")
let protected=fixture(unicode:false)
currentFixture.unavailableField=false; currentFixture.secureField=true; drain(0.25)
typeSource(protected)
require(physical(protected,code:49) == .pass,"known AX secure field blocks buffered replacement even if global SecureInput is off")
drain(0.5)
require(currentFixture.editor.string=="ghbdtn " && currentFixture.posted.isEmpty,"known protected field receives only native physical text")
protected.stop(); drain()
print("PASS: known AX secure field excludes fresh-buffer path")

let held=fixture(unicode:false); typeSource(held)
currentFixture.physicalModifiers = .maskShift
require(physical(held,code:36,flags:.maskShift) == .suppress,"ShiftEnter can wait boundedly for released modifiers")
drain(0.7)
require(currentFixture.editor.string=="ghbdtn\n","held modifier timeout preserves original word and ShiftEnter")
require(currentFixture.posted.allSatisfy { $0.1==36 && $0.2 == .maskShift },"held modifier never changes Backspace behavior")
held.stop(); drain()
print("PASS: bounded held-modifier abort preserves ShiftEnter")
testPhysicalInputIntegrity()
