import AppKit
import CoreGraphics
import SwitcherCore

// Every event enters the production EventTap parser. Navigation is deliberately
// not delivered to the private editor: its app-specific action is outside this
// contract. The original event must pass, with no replacement or synthetic text.
func testPhysicalInputIntegrity() {
 let group=ProcessInfo.processInfo.environment["MLS_PHYSICAL_GROUP"]
 if group != "interruption" { testNavigationIntegrity() }
 if group != "navigation" { testTapInterruptionIntegrity() }
}

private func testNavigationIntegrity() {
 let controls:[(UInt16,String)]=[(123,"Left"),(124,"Right"),(125,"Down"),(126,"Up"),
  (115,"Home"),(119,"End"),(53,"Escape"),(122,"F1"),(111,"F12"),(117,"ForwardDelete")]
 for unicode in [false,true] {
  for repeated in [false,true] {
   for (code,name) in controls {
    for phase in ["auto", "option-preflight", "option-capture", "idle"] {
     let label="\(unicode ? "Unicode" : "AX")/\(name)/repeat=\(repeated)/\(phase)"
     let engine=fixture(unicode:unicode, chromium:true)
     if phase == "option-preflight" || phase == "option-capture" {
      currentFixture.unavailableField=false
      awaitFixture("AX Option fixture bound") { engine.probeFocusReady }
     }
     typeSource(engine)
     var observed=false
     let navigate={
      observed=true
      require(physical(engine,code:code,autorepeat:repeated,deliver:false) == .pass,"\(label): navigation passes")
     }
     switch phase {
     case "auto":
      currentFixture.physicalModifiers = .maskShift
      require(physical(engine,code:49) == .suppress,"\(label): auto correction starts")
      navigate()
      currentFixture.physicalModifiers=[]
     case "option-preflight":
      // Two reads capture the value; the next read validates the buffered
      // source on Typist's queue before any destructive event is submitted.
      currentFixture.valueReadsBeforeHook=2
      currentFixture.valueReadHook=navigate
      option(engine)
     case "option-capture":
      currentFixture.valueReadHook=navigate
      option(engine)
     default: navigate()
     }
     drain()
     require(observed,"\(label): intended cancellation boundary reached")
     require(currentFixture.editor.string==original && currentFixture.posted.isEmpty,"\(label): cancellation preserves literal source without control-text replay")
     require(physical(engine,code:49) == .pass,"\(label): navigation resets stale correction candidate")
     require(currentFixture.editor.string==original+" ","\(label): subsequent ordinary Space reaches the editor once")
     engine.stop(); drain()
    }
   }
   print("PASS: \(unicode ? "Unicode" : "AX") navigation repeat=\(repeated), auto/Option capture/Option preflight/idle, source and native Space preserved")
  }
 }
}

private func key(_ engine:Engine, code:UInt16, down:Bool, flags:CGEventFlags=[], repeated:Bool=false) -> TapDecision {
 let event=CGEvent(keyboardEventSource:CGEventSource(stateID:.privateState),virtualKey:code,keyDown:down)!
 event.flags=flags; event.setIntegerValueField(.keyboardEventAutorepeat,value:repeated ? 1 : 0)
 return engine.probeEvent(event)
}

private func modifiers(_ engine:Engine, _ flags:CGEventFlags) {
 let event=CGEvent(keyboardEventSource:CGEventSource(stateID:.privateState),virtualKey:58,keyDown:false)!
 event.type = .flagsChanged; event.flags=flags
 require(engine.probeEvent(event) == .pass,"modifier events remain native")
}

private func interrupt(_ engine:Engine, _ type:CGEventType) {
 let event=CGEvent(source:nil)!; event.type=type
 require(engine.probeEvent(event) == .pass,"tap interruption passes")
}

private func click(_ engine:Engine) {
 let event=CGEvent(mouseEventSource:CGEventSource(stateID:.privateState),mouseType:.leftMouseDown,mouseCursorPosition:.zero,mouseButton:.left)!
 require(engine.probeEvent(event) == .pass,"click remains native")
}

private func testTapInterruptionIntegrity() {
 let shortcutFlags:CGEventFlags=[.maskCommand,.maskShift]
 for type in [CGEventType.tapDisabledByTimeout,.tapDisabledByUserInput] {
  for action in ["convert", "toggle"] {
   let engine=fixture(unicode:false) {
    let shortcut=Hotkey(keyCode:40,modifiers:[.command,.shift])
    if action == "convert" { $0.convertHotkey=shortcut } else { $0.toggleAutoHotkey=shortcut }
   }
   var toggles=0; engine.onAutoSwitchChanged={ _ in toggles += 1 }
   require(key(engine,code:40,down:true,flags:shortcutFlags) == .suppress,"\(action) shortcut consumed before interruption")
   interrupt(engine,type)
   // Its key-up occurred while the tap was disabled and was never observed.
   require(physical(engine,code:40) == .pass,"\(action): interruption retires ownership before next ordinary key")
   let fresh=KeyTranslator.characters(keyCode:40,flags:[])
   drain()
   require(currentFixture.editor.string==fresh && currentFixture.posted.isEmpty,"fresh ordinary key survives missed shortcut release")
   require(toggles == (action == "toggle" ? 1 : 0),"fresh ordinary key cannot retrigger consumed toggle")
   engine.stop(); drain()
  }

  // A modifier gesture interrupted before release must not turn into Option
  // conversion. A subsequent complete Option gesture remains usable.
  let modifier=fixture(unicode:false); typeSource(modifier)
  modifiers(modifier,.maskAlternate); interrupt(modifier,type); modifiers(modifier,[])
  drain()
  require(currentFixture.editor.string==original,"interrupted Option release cannot convert")
  currentFixture.unavailableField=false
  awaitFixture("preexisting word after interruption uses AX") { modifier.probeFocusReady }
  option(modifier); drain()
  require(currentFixture.editor.string==converted,"fresh Option works after interrupted gesture")
  modifier.stop(); drain()

  // Exercise the real gesture and coordinator while paused: hold cannot open
  // the microphone or start model preparation. Cancellation is visible through
  // the coordinator's ordinary status callback, not private gesture state.
  let speech=fixture(unicode:false); speech.dictation.paused=true
  var cancellations=0; speech.dictation.onStatus={ if $0.isEmpty { cancellations += 1 } }
  require(key(speech,code:49,down:true,flags:[.maskControl,.maskAlternate]) == .suppress,"dictation hold consumes Space")
  interrupt(speech,type)
  require(physical(speech,code:49) == .pass,"lost dictation release cannot consume fresh ordinary Space")
  require(key(speech,code:53,down:true) == .pass,"interruption retires requested dictation before Escape")
  require(key(speech,code:53,down:false) == .pass,"ordinary Escape release passes")
  drain()
  require(cancellations==1 && !speech.dictation.isActive,"interrupted dictation hold is cancelled without microphone access")
  require(currentFixture.editor.string==" ","fresh Space reaches editor after dictation interruption")
  speech.stop(); drain()

  for unicode in [false,true] {
   let pending=fixture(unicode:unicode); typeSource(pending)
   currentFixture.physicalModifiers = .maskShift
   require(physical(pending,code:49) == .suppress,"replacement started before tap interruption")
   interrupt(pending,type)
   currentFixture.physicalModifiers=[]
   drain()
   require(currentFixture.editor.string==original && currentFixture.posted.isEmpty,"tap interruption cancels pending replacement without mutation")
   require(physical(pending,code:49) == .pass,"fresh separator not owned by interrupted stream")
   require(currentFixture.editor.string==original+" ","fresh separator survives interruption")
   pending.stop(); drain()
  }
  print("PASS: \(type) retires convert/toggle/dictation/modifier ownership and cancels buffered pending replacement")
 }

 // Counterexample: click cancels text ownership, but a shortcut still held
 // across it continues to own repeats and its matching release.
 let clicked=fixture(unicode:false) { $0.toggleAutoHotkey=Hotkey(keyCode:40,modifiers:[.command,.shift]) }
 var toggles=0; clicked.onAutoSwitchChanged={ _ in toggles += 1 }
 require(key(clicked,code:40,down:true,flags:shortcutFlags) == .suppress,"toggle begins held shortcut")
 click(clicked)
 require(key(clicked,code:40,down:true,repeated:true) == .suppress,"click retains held shortcut repeat ownership after modifier release")
 require(key(clicked,code:40,down:false) == .suppress,"click retains held shortcut key-up ownership")
 require(toggles==1,"held repeat cannot toggle again")
 require(physical(clicked,code:40) == .pass,"ordinary key works after actual shortcut release")
 clicked.stop(); drain()

 // Recorder transitions also lose releases. Ending recording while Option is
 // still down must not dispatch the recorder's gesture as a conversion.
 let recorded=fixture(unicode:false) { $0.toggleAutoHotkey=Hotkey(keyCode:40,modifiers:[.command,.shift]) }
 require(key(recorded,code:40,down:true,flags:shortcutFlags) == .suppress,"shortcut precedes recorder")
 recorded.isRecordingHotkey=true
 require(physical(recorded,code:40) == .pass,"recording clears prior consumed ownership")
 modifiers(recorded,.maskAlternate)
 recorded.isRecordingHotkey=false
 modifiers(recorded,[]); drain()
 require(currentFixture.editor.string==KeyTranslator.characters(keyCode:40,flags:[]),"recorder modifier release does not convert typed text")
 require(physical(recorded,code:40) == .pass,"ordinary input resumes after recording")
 recorded.stop(); drain()
 print("PASS: clicks retain actual held shortcut ownership; recording transitions clear stale ownership and modifier taps")
}
