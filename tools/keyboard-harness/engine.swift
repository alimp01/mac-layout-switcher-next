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
 var chromium = true
 var physicalModifiers: CGEventFlags = []
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
   if resolvingPhysicalKey { posted.append((event.type,code,event.flags)) }
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

func fixture(unicode:Bool, chromium: Bool = true, configure: (inout AppConfig) -> Void = { _ in }) -> Engine {
 harnessFrontPID=harnessPID
 currentFixture=FixtureAX(unicode:unicode)
 currentFixture.chromium=chromium
 currentFixture.editor.string=""; currentFixture.editor.setSelectedRange(NSRange(location:0,length:0))
 let directory=URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
 let config=Config(directory:directory); config.update { $0.excludedApps=[]; $0.sounds=false; configure(&$0) }
 let engine=Engine(config:config); require(engine.start(),"inert registration starts")
 currentFixture.syntheticFilter = { [weak engine] in engine?.probeEvent($0) ?? .pass }
 let event=CGEvent(keyboardEventSource:CGEventSource(stateID:.privateState),virtualKey:58,keyDown:false)!
 event.type = .flagsChanged; event.flags=[]; _=engine.probeEvent(event)
 awaitFixture("initial AX target is sampled before ready-field scenarios") { engine.probeFocusReady }
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
if ProcessInfo.processInfo.environment["MLS_OPTION_ONLY"] != "1" { testPhysicalInputIntegrity() }
if ProcessInfo.processInfo.environment["MLS_PHYSICAL_ONLY"] == "1" { exit(0) }
for unicode in [false,true] {
 let engine=fixture(unicode:unicode); typeSource(engine)
 let oldEditor=currentFixture.editor
 currentFixture.activeField=1
 currentFixture.editor.string="context ghbdtn"
 currentFixture.editor.setSelectedRange(NSRange(location:14,length:0))
 option(engine); drain(0.65)
 require(oldEditor.string==original,"Option preserves previously sampled field")
 require(currentFixture.editor.string=="context привет","Option converts fresh field last word with caret at end before next sample: expected=context привет, actual=\(currentFixture.editor.string.debugDescription)")
 require(currentFixture.editor.selectedRange()==NSRange(location:14,length:0),"Option keeps caret after new-field word")
 engine.stop(); drain()
}
print("PASS: Option accepts fresh field before sampler and discards stale buffered word")
func labels(_ view: NSView) -> [String] {
 (view as? NSTextField).map { [$0.stringValue] } ?? view.subviews.flatMap(labels)
}
let denied=fixture(unicode:false)
currentFixture.editor.string="ghbdtn"; currentFixture.editor.setSelectedRange(NSRange(location:6,length:0))
let deniedWindows=Set(NSApplication.shared.windows.map(ObjectIdentifier.init))
currentFixture.isTrusted=false
option(denied); drain(0.4)
let deniedNotice=NSApplication.shared.windows.filter { !deniedWindows.contains(ObjectIdentifier($0)) }.flatMap { $0.contentView.map(labels) ?? [] }.joined(separator:"\n")
require(deniedNotice.contains("У Mac Layout Switcher нет разрешения «Универсальный доступ»"),"Option reports actual process trust denial separately from unavailable editor")
require(currentFixture.editor.string=="ghbdtn","trust denial preserves source")
denied.stop(); drain()
print("PASS: Option distinguishes actual process trust denial")
let changedContext=fixture(unicode:false)
currentFixture.editor.string="context ghbdtn"; currentFixture.editor.setSelectedRange(NSRange(location:14,length:0))
currentFixture.valueReadHook={ currentFixture.editor.string="changed ghbdtn"; currentFixture.editor.setSelectedRange(NSRange(location:14,length:0)) }
option(changedContext); drain(0.5)
require(currentFixture.editor.string=="changed ghbdtn","Option cancels when field text changes during capture even outside source word")
changedContext.stop(); drain()
print("PASS: Option cancels changed context during capture")
for unicode in [false,true] {
 let buffered=fixture(unicode:unicode); typeSource(buffered)
 option(buffered); drain(0.4)
 require(currentFixture.editor.string==converted,"same-field Option converts buffered word")
 option(buffered); drain(0.4)
 require(currentFixture.editor.string==original,"second Option restores buffered conversion")
 buffered.stop(); drain()
 let undo=fixture(unicode:unicode); typeSource(undo)
 require(physical(undo,code:49) == .suppress,"auto correction before Option undo")
 drain(0.4); require(currentFixture.editor.string==converted+" ","verified auto correction before undo")
 option(undo); drain(0.4)
 require(currentFixture.editor.string==original+" ","Option undoes recent automatic conversion")
 undo.stop(); drain()
 let selected=fixture(unicode:unicode); typeSource(selected)
 currentFixture.editor.string="🙂 ghbdtn хвост"; currentFixture.editor.setSelectedRange(NSRange(location:3,length:6))
 option(selected); drain(0.4)
 require(currentFixture.editor.string=="🙂 привет хвост","selected Option takes priority over stale buffered word and preserves emoji/context")
 selected.stop(); drain()
 let word=fixture(unicode:unicode)
 currentFixture.editor.string="context ghbdtn  "; currentFixture.editor.setSelectedRange(NSRange(location:16,length:0))
 option(word); drain(0.4)
 require(currentFixture.editor.string=="context привет  ","same-field Option recovers preexisting word and trailing spaces")
 word.stop(); drain()
}
let empty=fixture(unicode:false); LayoutSwitcher.language = .en
option(empty); drain(0.4)
require(currentFixture.editor.string.isEmpty && LayoutSwitcher.language == .ru,"empty field Option switches layout")
empty.stop(); drain()
print("PASS: Option same-field buffered/fallback/selection/undo/empty behavior on AX and Unicode")
for mode in ["field", "pid", "key", "click", "caret"] {
 let engine=fixture(unicode:false)
 currentFixture.editor.string="context ghbdtn"; currentFixture.editor.setSelectedRange(NSRange(location:14,length:0))
 currentFixture.editors[1].string="another ghbdtn"; currentFixture.editors[1].setSelectedRange(NSRange(location:14,length:0))
 let typed=KeyTranslator.characters(keyCode:5,flags:[])
 currentFixture.valueReadHook={
  switch mode {
  case "field": currentFixture.activeField=1
  case "pid": harnessFrontPID=harnessPID+1
  case "key": _=physical(engine,code:5)
  case "click":
   let click=CGEvent(mouseEventSource:CGEventSource(stateID:.privateState),mouseType:.leftMouseDown,mouseCursorPosition:.zero,mouseButton:.left)!
   _=engine.probeEvent(click)
  default: currentFixture.editor.setSelectedRange(NSRange(location:7,length:0))
  }
 }
 option(engine); drain(0.5)
 require(currentFixture.editors[0].string=="context ghbdtn"+(mode == "key" ? typed : ""),"Option cancels during capture on \(mode)")
 require(currentFixture.editors[1].string=="another ghbdtn","Option never follows changed field")
 engine.stop(); drain()
}
print("PASS: Option field/PID/caret/key/click changes during capture cancel without writing")
for (mode,expected) in [("secure","Включён защищённый ввод"),("protected","Включён защищённый ввод"),
 ("field","Редактор не предоставил доступное поле ввода"),("range","Редактор не сообщил положение курсора"),
 ("text","Редактор не предоставил текст для проверки замены")] {
 let engine=fixture(unicode:false)
 currentFixture.editor.string="ghbdtn"; currentFixture.editor.setSelectedRange(NSRange(location:6,length:0))
 let windows=Set(NSApplication.shared.windows.map(ObjectIdentifier.init))
 switch mode {
 case "secure": currentFixture.isSecure=true
 case "protected": currentFixture.secureField=true
 case "field": currentFixture.unavailableField=true
 case "range": currentFixture.unavailableSelection=true
 default: currentFixture.unavailableText=true
 }
 option(engine); drain(0.5)
 let message=NSApplication.shared.windows.filter { !windows.contains(ObjectIdentifier($0)) }.flatMap { $0.contentView.map(labels) ?? [] }.joined(separator:"\n")
 require(message.contains(expected),"Option gives distinct \(mode) capture reason")
 require(!message.contains("нет разрешения"),"Option does not blame permissions when process is trusted")
 require(currentFixture.editor.string=="ghbdtn","capture refusal keeps source")
 engine.stop(); drain()
}
let lazy=fixture(unicode:true)
currentFixture.editor.string="ghbdtn"; currentFixture.editor.setSelectedRange(NSRange(location:6,length:0)); currentFixture.needsBootstrap=true
option(lazy)
awaitFixture("Option bounded bootstrap captures lazily exposed field") { currentFixture.editor.string=="привет" }
lazy.stop(); drain()
let wrapped=fixture(unicode:true)
currentFixture.editor.string="ghbdtn"; currentFixture.editor.setSelectedRange(NSRange(location:6,length:0))
currentFixture.needsBootstrap=true; currentFixture.bootstrapWrapper=true
option(wrapped)
awaitFixture("Option bootstrap may replace non-editable AX wrapper with actual text field") { currentFixture.editor.string=="привет" }
wrapped.stop(); drain()
print("PASS: Option distinct secure/field/range/text reasons and bounded bootstrap")
let bootstrapChanged=fixture(unicode:false)
currentFixture.editor.string="ghbdtn"; currentFixture.editor.setSelectedRange(NSRange(location:6,length:0))
currentFixture.editors[1].string="ghbdtn"; currentFixture.editors[1].setSelectedRange(NSRange(location:6,length:0))
currentFixture.unavailableSelection=true
currentFixture.bootstrapHook={ currentFixture.activeField=1; currentFixture.unavailableSelection=false }
option(bootstrapChanged); drain(0.5)
require(currentFixture.editors.allSatisfy { $0.string=="ghbdtn" },"bootstrap must not follow an already observed editable field to another field")
bootstrapChanged.stop(); drain()
for mode in ["fallback", "buffered", "selected"] {
 let engine=fixture(unicode:false)
 if mode == "buffered" { typeSource(engine) }
 let source = mode == "buffered" ? original : "ghbdtn"
 currentFixture.editor.string="context "+source
 currentFixture.editor.setSelectedRange(NSRange(location:mode == "selected" ? 8 : 8+source.utf16.count,length:mode == "selected" ? source.utf16.count : 0))
 // The last capture read returns its prior snapshot while external text
 // changes. The later write must still validate the original captured value.
 currentFixture.valueReadsBeforeHook=1
 currentFixture.valueReadHook={
  currentFixture.editor.string="changed "+source
  currentFixture.editor.setSelectedRange(NSRange(location:mode == "selected" ? 8 : 8+source.utf16.count,length:mode == "selected" ? source.utf16.count : 0))
 }
 option(engine); drain(0.5)
 require(currentFixture.editor.string=="changed "+source,"Option validates full captured value before \(mode) write")
 engine.stop(); drain()
}
let beforeCapture=fixture(unicode:false)
currentFixture.editor.string="ghbdtn"; currentFixture.editor.setSelectedRange(NSRange(location:6,length:0))
option(beforeCapture); _=physical(beforeCapture,code:5)
let beforeCaptureText=currentFixture.editor.string
drain(0.4)
require(currentFixture.editor.string==beforeCaptureText,"physical input before deferred Option begins cancels input sequence")
beforeCapture.stop(); drain()
print("PASS: Option keeps editable-field bootstrap identity, validates full capture before every write route, and cancels before dispatch")
let unreadableSelection=fixture(unicode:false); typeSource(unreadableSelection)
currentFixture.editor.setSelectedRange(NSRange(location:2,length:2)); currentFixture.unavailableText=true
option(unreadableSelection); drain(0.5)
require(currentFixture.editor.string==original && currentFixture.posted.isEmpty,"known nonempty unreadable selection cannot fall through to fresh-buffer deletion")
unreadableSelection.stop(); drain()
print("PASS: unreadable nonempty selection preserves source instead of buffered fallback")
if ProcessInfo.processInfo.environment["MLS_OPTION_ONLY"] == "1" { exit(0) }
for unicode in [false,true] {
 let route=unicode ? "Unicode" : "AX"
 for (code,flags,separator) in [(UInt16(49),CGEventFlags()," "),(UInt16(36),CGEventFlags(),"\n"),(UInt16(36),CGEventFlags.maskShift,"\n"),(UInt16(48),CGEventFlags(),"\t")] {
  let engine=fixture(unicode:unicode); typeSource(engine)
  currentFixture.selectionHook={ _=physical(engine,code:code,autorepeat:true,flags:flags) }
  require(physical(engine,code:code,flags:flags) == .suppress,"automatic separator suppresses initial physical down")
  drain(0.7)
  require(currentFixture.editor.string==converted+separator+separator,"entire corrected word plus both separators survive \(route)/\(code): actual=\(currentFixture.editor.string.debugDescription)")
  postedKeys(code==49 ? [49] : [code,code],flags:flags)
  engine.stop(); drain()
 }
 print("PASS: \(route) Space/Enter/Shift+Enter/Tab repeat after temporary selection, down/up, flags, own markers")
 // The repeated printable character is captured from the original layout;
 // it is replayed as Unicode rather than translated after layout switching.
 for repeatCode:UInt16 in [5,51] {
  let engine=fixture(unicode:unicode); typeSource(engine)
  let repeated=KeyTranslator.characters(keyCode:repeatCode,flags:[])
  currentFixture.selectionHook={ require(physical(engine,code:repeatCode,autorepeat:true) == .suppress,"busy text-edit repeat queued") }
  require(physical(engine,code:49) == .suppress,"auto correction queued before repeat")
  drain(0.7)
  let expected=repeatCode==51 ? converted : converted+" "+repeated
  require(currentFixture.editor.string==expected,"printable/backspace repeat follows complete replacement")
  postedKeys([repeatCode==51 ? 51 : 0])
  engine.stop(); drain()
 }
 print("PASS: \(route) printable and Backspace repeats preserve text-edit order")
 let series=fixture(unicode:unicode); typeSource(series)
 currentFixture.selectionHook={ for _ in 0..<3 { require(physical(series,code:49,autorepeat:true) == .suppress,"every repeat in held series is queued") } }
 require(physical(series,code:49) == .suppress,"series follows initial correction")
 drain(0.7)
 require(currentFixture.editor.string==converted+"    ","three repeated spaces delivered once after full correction")
 postedKeys([49,49,49]); series.stop(); drain()
 print("PASS: \(route) three queued repeats arrive exactly once")
 let engine=fixture(unicode:unicode); typeSource(engine)
 let following=KeyTranslator.characters(keyCode:5,flags:[])
 currentFixture.selectionHook={
  require(physical(engine,code:36,autorepeat:true) == .suppress,"repeat Enter queued")
  require(physical(engine,code:5) == .suppress,"fast next letter queued behind navigation")
 }
 require(physical(engine,code:36) == .suppress,"initial Enter queued")
 drain(0.7)
 require(currentFixture.editor.string==converted+"\n\n"+following,"fast next letter follows both Enter deliveries")
 postedKeys([36,36,0]); engine.stop(); drain()
 print("PASS: \(route) original keyUp/repeated down-up/fast letter after queued Enter")
 // A quick next word still reaches EngineCore during ordinary replay; its
 // literal text must follow the first corrected word without stale conversion.
 let next=fixture(unicode:unicode); typeSource(next)
 let latinCodes:[UInt16]=[31,6,31,45]
 let nextWord=startsEnglish ? "ozon" : "щящт"
 currentFixture.selectionHook={ for code in latinCodes { require(physical(next,code:code) == .suppress,"rapid next word queued") } }
 require(physical(next,code:49) == .suppress,"initial Space queued")
 drain(0.7)
 require(currentFixture.editor.string==converted+" "+nextWord,"rapid next word kept after correction")
 postedKeys([0,0,0,0]); next.stop(); drain()
 print("PASS: \(route) fast next word remains in original captured layout")
}
// Controls and unrelated navigation keep the preexisting cancellation contract.
// The external application's command action is deliberately not modeled here:
// the real EventTap/Translator/Engine still must pass it and cancel its permit.
for (code,flags) in [(UInt16(123),CGEventFlags()),(UInt16(124),CGEventFlags()),(UInt16(115),CGEventFlags()),(UInt16(119),CGEventFlags()),(UInt16(53),CGEventFlags()),(UInt16(122),CGEventFlags()),(UInt16(5),CGEventFlags.maskCommand),(UInt16(5),CGEventFlags.maskControl)] {
 let engine=fixture(unicode:false); typeSource(engine)
 currentFixture.selectionHook={ require(physical(engine,code:code,autorepeat:true,flags:flags,deliver:false) == .pass,"navigation/command repeat passes and cancels replacement") }
 require(physical(engine,code:49) == .suppress,"correction starts before unrelated navigation")
 drain(0.7)
 require(currentFixture.editor.string==original && currentFixture.posted.isEmpty,"cancelled correction cannot modify or replay into unrelated navigation")
 engine.stop(); drain()
}
let clicked=fixture(unicode:false); typeSource(clicked)
currentFixture.selectionHook={
 let click=CGEvent(mouseEventSource:CGEventSource(stateID:.privateState),mouseType:.leftMouseDown,mouseCursorPosition:.zero,mouseButton:.left)!
 require(clicked.probeEvent(click) == .pass,"physical click invalidates correction")
}
require(physical(clicked,code:49) == .suppress,"correction starts before click")
drain(0.7)
require(currentFixture.editor.string==original && currentFixture.posted.isEmpty,"click cancels old target without source mutation")
clicked.stop(); drain()
print("PASS: Left/Right/Home/End/Esc/F1/Cmd/Ctrl autorepeat and click preserve cancellation")
func viewText(_ view:NSView) -> [String] {
 (view as? NSTextView).map { [$0.string] } ?? view.subviews.flatMap(viewText)
}
for unicode in [false,true] {
 let engine=fixture(unicode:unicode); typeSource(engine)
 let previousWindows=Set(NSApplication.shared.windows.map(ObjectIdentifier.init))
 currentFixture.ignoreWrites=true
 currentFixture.selectionHook={ require(physical(engine,code:36,autorepeat:true) == .suppress,"uncertain-path Enter repeat queued before failure known") }
 require(physical(engine,code:49) == .suppress,"attempted correction owns original Space")
 drain(0.7)
 require(currentFixture.editor.string==original && currentFixture.posted.isEmpty,"no-op write retains source and never submits queued repeat Enter")
 require(currentFixture.suppressedUpsValid,"uncertain queue still owns physical keyUps")
 let recovery=NSApplication.shared.windows.filter { !previousWindows.contains(ObjectIdentifier($0)) && $0.title=="Конвертация раскладки" }.flatMap { $0.contentView.map(viewText) ?? [] }.joined(separator:"\n")
 require(recovery.contains(original) && recovery.contains(converted) && recovery.contains("⏎"),"production recovery retains original, planned replacement and held repeat Enter")
 engine.stop(); drain()
}
print("PASS: unconfirmed AX/Unicode keeps source, planned replacement, repeat Enter and keyUp without submission")
for repeatCode:UInt16 in [49,36,48,5,51] {
 let engine=fixture(unicode:false); typeSource(engine)
 let appended=repeatCode==49 ? " " : repeatCode==36 ? "\n" : repeatCode==48 ? "\t" : KeyTranslator.characters(keyCode:repeatCode,flags:[])
 require(physical(engine,code:repeatCode,autorepeat:true) == .pass,"outside busy repeat passes natively")
 let expected=repeatCode==51 ? String(original.dropLast()) : original+appended
 require(currentFixture.editor.string==expected,"outside busy repeat preserves physical edit")
 require(physical(engine,code:49) == .pass,"repeat cleared correction buffer instead of growing it")
 require(currentFixture.editor.string==expected+" ","no delayed correction after outside-busy repeat")
 require(currentFixture.posted.isEmpty,"outside-busy repeat is never replayed")
 engine.stop(); drain()
}
print("PASS: outside-busy printable/Backspace/Space/Enter/Tab repeats pass and reset correction candidates")
print("Production EventTap→KeyTranslator→Engine regression passed. Private AppKit receiver; native physical-post resolution injected; no hardware/WindowServer delivery proof.")
