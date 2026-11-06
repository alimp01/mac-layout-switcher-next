#if os(macOS)
import AppKit

/// An explicit failed conversion is explained without taking editor focus.
final class ConversionNotice: NSObject {
    private let panel: NSPanel
    private let presentsWindow: Bool
    private let label = NSTextField(wrappingLabelWithString: "")
    private var withheldInput = ""
    private var replacements: [(original: String, planned: String)] = []
    private let recoveryScroll = NSScrollView()
    private let recoveryText = NSTextView()

    init(panel: NSPanel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 390, height: 130),
                                 styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false),
         presentsWindow: Bool = true) {
        self.panel = panel
        self.presentsWindow = presentsWindow
        super.init()
        label.isSelectable = true
        panel.title = "Next · Конвертация раскладки"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        let close = NSButton(title: "Закрыть", target: self, action: #selector(dismiss))
        recoveryScroll.hasVerticalScroller = true
        recoveryScroll.borderType = .bezelBorder
        recoveryScroll.documentView = recoveryText
        recoveryScroll.isHidden = true
        recoveryText.isEditable = false
        recoveryText.isSelectable = true
        recoveryText.isVerticallyResizable = true
        recoveryText.isHorizontallyResizable = false
        recoveryText.autoresizingMask = [.width]
        recoveryText.textContainer?.widthTracksTextView = true
        recoveryText.textContainer?.containerSize = NSSize(width: 358, height: CGFloat.greatestFiniteMagnitude)
        recoveryText.frame = NSRect(x: 0, y: 0, width: 358, height: 160)
        recoveryText.font = .systemFont(ofSize: 14)
        let stack = NSStackView(views: [label, recoveryScroll, close])
        stack.detachesHiddenViews = true
        recoveryScroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        recoveryScroll.heightAnchor.constraint(equalToConstant: 160).isActive = true
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        panel.contentView = content
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -16),
            label.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        if let screen = NSScreen.main {
            panel.setFrameTopLeftPoint(NSPoint(x: screen.visibleFrame.maxX - 410,
                                               y: screen.visibleFrame.maxY - 30))
        }
    }
    func appendWithheldInput(_ text: String) {
        withheldInput += text
        updateRecoveryText()
        recoveryScroll.isHidden = false
        showRecovery()
    }
    func retainReplacement(original: String, replacement: String) {
        replacements.append((original, replacement))
        updateRecoveryText()
        recoveryScroll.isHidden = false
        showRecovery()
    }
    private func updateRecoveryText() {
        let entries = replacements.map { "Исходный текст:\n\($0.original)\n\nТекст для замены:\n\($0.planned)" }
        recoveryText.string = entries.isEmpty ? withheldInput : entries.joined(separator: "\n\n────────\n\n") + "\n\nУдержанный ввод:\n" + withheldInput
    }
    private func showRecovery() {
        let saved = replacements.isEmpty
            ? "Неотправленный ввод сохранён ниже: его можно выделить и скопировать."
            : "Исходный текст, текст для замены и неотправленный ввод сохранены ниже: их можно выделить и скопировать."
        show(message: "Не удалось подтвердить замену: текст мог быть удалён или изменён частично. Проверьте поле перед ручным восстановлением. \(saved) ⏎ — Enter, ⇥ — Tab, ⌫ — Backspace; эти клавиши не отправлены.")
    }
    func showUncertain() {
        if !withheldInput.isEmpty {
            appendWithheldInput("\n")
        } else if replacements.isEmpty {
            recoveryScroll.isHidden = true
            show(message: "Не удалось подтвердить замену. Текст мог измениться частично. Отправка Enter/Tab остановлена. Проверьте слово перед продолжением; повторной замены не было.")
        } else { showRecovery() }
    }
    func show(message: String = "Текст не изменён: поле, курсор или выделение изменились либо редактор не поддерживает проверяемую замену. Повторите Option в нужном поле.") {
        label.stringValue = message
        let height = max(130, min(500, label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: 358, height: 10_000)).height ?? 100) + 75)
        panel.setContentSize(NSSize(width: 390, height: height + (recoveryScroll.isHidden ? 0 : 172)))
        panel.contentView?.layoutSubtreeIfNeeded()
        recoveryText.setFrameSize(NSSize(width: recoveryScroll.contentSize.width, height: max(160, recoveryText.frame.height)))
        if presentsWindow { panel.orderFrontRegardless() }
    }
    /// A later successful conversion must not erase unrecovered physical input.
    func hide() { if withheldInput.isEmpty && replacements.isEmpty { panel.orderOut(nil) } }
    @objc func dismiss() {
        panel.orderOut(nil)
        recoveryScroll.isHidden = true
        withheldInput = ""
        replacements = []
        recoveryText.string = ""
    }
}
#endif
