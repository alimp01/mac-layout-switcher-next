import AppKit
import CoreGraphics
import Carbon.HIToolbox
import CryptoKit
import SwitcherCore

// Capture real TIS data once. The user may keep changing the system layout
// while this owned fixture runs; its input source must remain internally
// consistent. No source is selected in macOS and UCKeyTranslate is unchanged.
private let harnessKeyboardSource: TISInputSource? = {
    let identifier = ProcessInfo.processInfo.environment["MLS_FIXTURE_INPUT_SOURCE_ID"] ?? "com.apple.keylayout.ABC"
    guard ["com.apple.keylayout.ABC", "com.apple.keylayout.RussianWin"].contains(identifier) else { return nil }
    do {
        let properties = [kTISPropertyInputSourceID as String: identifier, kTISPropertyInputSourceIsEnabled as String: true] as CFDictionary
        guard let sources = TISCreateInputSourceList(properties, false)?.takeRetainedValue() as? [TISInputSource] else { return nil }
        return sources.first
    }
}()
private let harnessKeyboardData: CFData? = {
    guard let source = harnessKeyboardSource,
          let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
    return CFDataCreateCopy(nil, Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue())
}()
func harnessCopyKeyboardInputSource() -> Unmanaged<TISInputSource>? {
    harnessKeyboardSource.map { Unmanaged.passRetained($0) }
}
func harnessKeyboardLayoutData(_ source: TISInputSource) -> UnsafeMutableRawPointer? {
    guard let original = harnessKeyboardSource, CFEqual(source, original), let data = harnessKeyboardData else { return nil }
    return Unmanaged.passUnretained(data).toOpaque()
}
func harnessKeyboardSnapshotDescription() -> String {
    guard let source = harnessKeyboardSource, let data = harnessKeyboardData,
          let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "unavailable" }
    let identifier = Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    let digest = SHA256.hash(data: data as Data).map { String(format: "%02x", $0) }.joined()
    return "source=\(identifier); uchrBytes=\(CFDataGetLength(data)); uchrSHA256=\(digest)"
}
// Engine's selected destination is local to the fixture.
public enum LayoutSwitcher {
    static var language: Lang = .en
    public static func current() -> Lang? { language }
    @discardableResult public static func select(_ language: Lang) -> Bool {
        self.language = language
        return true
    }
}
let harnessPID: pid_t = 12345
var harnessFrontPID: pid_t = harnessPID
var currentFixture: FixtureAX!
var harnessAccessibility: any DictationAccessibility { currentFixture! }
// Typist's real Self.post already applied its marker and delay. Only the final
// global CGEvent post is replaced with delivery to the private AppKit fixture.
func harnessPost(_ event: CGEvent) {
    currentFixture.receive(event, resolvingPhysicalKey: true)
}
