import AppKit

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let previousKeyWindow = app.keyWindow
let hud = DictationPanel()
let sample = "Проверка: русский текст 🦆 виден.\n" + String(repeating: "Длинный результат с переносами и emoji 🙂.\n", count: 80)
let clipboardCount = NSPasteboard.general.changeCount
hud.show("Поле изменилось. Скопируйте результат вручную.", primaryTitle: "Копировать", text: sample)
RunLoop.current.run(until: Date().addingTimeInterval(0.1))
let window = app.windows.first { $0.title == "Next · Диктовка · GigaAM v3" }!
let content = window.contentView!
content.layoutSubtreeIfNeeded()
let text = descendants(content).compactMap { $0 as? NSTextView }.first!
let scroll = text.enclosingScrollView!
require(text.string == sample, "fallback text preserved")
require(text.frame.width > 100 && text.textContainer!.containerSize.width > 100, "fallback has a visible document and text-container width")
text.layoutManager!.ensureLayout(for: text.textContainer!)
let used = text.layoutManager!.usedRect(for: text.textContainer!)
require(used.width > 100 && used.height > scroll.contentSize.height, "long result lays out visible glyphs and scrolls")
require(text.frame.height >= used.height, "document grows to show every line")
require(text.isSelectable && !text.isEditable, "result selectable without editing")
text.setSelectedRange(NSRange(location: 0, length: 8))
require(text.selectedRange() == NSRange(location: 0, length: 8), "user can select result")
require(app.keyWindow === previousKeyWindow, "show does not steal keyboard focus")
require(NSPasteboard.general.changeCount == clipboardCount, "show does not touch clipboard")
let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds)!
content.cacheDisplay(in: content.bounds, to: bitmap)
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
hud.hide()
print("PASS: production panel visible glyphs, long text scrolling, selection, nonactivation, clipboard preservation")
