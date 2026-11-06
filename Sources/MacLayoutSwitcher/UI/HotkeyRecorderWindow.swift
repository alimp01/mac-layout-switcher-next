// Слой UI macOS. Весь файл — под #if os(macOS): на Linux target собирается в
// пустой executable. Код собирается вслепую (компиляции на Linux нет) — только
// документированный AppKit, консервативно; вся проверяемая логика хоткеев живёт
// в `SwitcherCore.Hotkey` и покрыта тестами на Linux.
#if os(macOS)
import AppKit
import SwitcherCore

/// Окно «Настройка горячих клавиш»: две строки (Конвертация / Вкл-выкл авто),
/// у каждой текущее значение (`Hotkey.displayName`), кнопка «Записать» (ловит
/// следующее сочетание локальным NSEvent-монитором в пределах окна) и «Сброс».
/// Значения пишутся в общий `Config`; работающий `Engine` читает их живьём при
/// каждом событии, поэтому смена применяется сразу (перезапуск не требуется).
public final class HotkeyRecorderWindow: NSObject, NSWindowDelegate {

    public var onRecordingChanged: ((Bool) -> Void)?
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let config: Config
    private var window: NSWindow?

    // Строки: 0 — конвертация, 1 — переключение авто.
    private var valueLabels: [Int: NSTextField] = [:]
    private var recordButtons: [Int: NSButton] = [:]

    // Состояние записи.
    private var recordingTag: Int?
    private var pendingModifiers: Set<Hotkey.Modifier> = []
    private var monitor: Any?

    public init(config: Config) {
        self.config = config
        super.init()
        NotificationCenter.default.addObserver(self,
            selector: #selector(cancelRecording),
            name: NSApplication.didResignActiveNotification, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    /// Показывает окно (создаёт при первом вызове), выводит на передний план.
    public func show() {
        if window == nil { build() }
        refreshValues()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Построение окна

    private func build() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 250),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        win.title = "Next · Горячие клавиши"
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.center()

        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 16
        rows.translatesAutoresizingMaskIntoConstraints = false

        rows.addArrangedSubview(makeRow(
            tag: 0, title: "Конвертация / откат:"))
        rows.addArrangedSubview(makeRow(
            tag: 1, title: "Вкл/выкл авто:"))

        rows.addArrangedSubview(makeRow(tag: 2, title: "Диктовка (удерживать):"))
        errorLabel.textColor = .systemRed
        errorLabel.font = .systemFont(ofSize: 11)
        rows.addArrangedSubview(errorLabel)
        let hint = NSTextField(labelWithString:
            "«Записать» — нажмите нужное сочетание. Esc — отмена записи.")
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        rows.addArrangedSubview(hint)

        let content = NSView()
        content.addSubview(rows)
        NSLayoutConstraint.activate([
            rows.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            rows.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            rows.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            rows.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20),
        ])
        win.contentView = content
        window = win
    }

    private func makeRow(tag: Int, title: String) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let value = NSTextField(labelWithString: "—")
        value.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
        value.alignment = .center
        value.setContentHuggingPriority(.required, for: .horizontal)
        valueLabels[tag] = value

        let record = NSButton(title: "Записать", target: self, action: #selector(startRecording(_:)))
        record.tag = tag
        record.bezelStyle = .rounded
        recordButtons[tag] = record

        let reset = NSButton(title: "Сброс", target: self, action: #selector(resetRow(_:)))
        reset.tag = tag
        reset.bezelStyle = .rounded

        let row = NSStackView(views: [label, value, record, reset])
        row.orientation = .horizontal
        row.spacing = 10
        row.alignment = .centerY
        NSLayoutConstraint.activate([
            label.widthAnchor.constraint(equalToConstant: 150),
            value.widthAnchor.constraint(greaterThanOrEqualToConstant: 90),
        ])
        return row
    }

    private func refreshValues() {
        valueLabels[2]?.stringValue = config.config.dictationHotkey.displayName
        valueLabels[0]?.stringValue = config.config.convertHotkey.displayName
        valueLabels[1]?.stringValue = config.config.toggleAutoHotkey?.displayName ?? "не назначено"
    }

    // MARK: - Запись сочетания

    @objc private func startRecording(_ sender: NSButton) {
        if monitor != nil { stopRecording() }
        onRecordingChanged?(true)
        errorLabel.stringValue = ""
        recordingTag = sender.tag
        pendingModifiers = []
        for (_, b) in recordButtons { b.isEnabled = false }
        sender.title = "Нажмите клавишу…"
        sender.isEnabled = true

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.capture(event)
            return nil // событие поглощается окном записи
        }
    }

    private func capture(_ event: NSEvent) {
        guard let tag = recordingTag else { return }
        let mods = Self.modifiers(from: event.modifierFlags)

        switch event.type {
        case .keyDown:
            // Esc без модификаторов — отмена записи.
            if event.keyCode == 53, mods.isEmpty {
                stopRecording()
                refreshValues()
                return
            }
            finalize(tag: tag, hotkey: Hotkey(keyCode: event.keyCode, modifiers: mods))
        case .flagsChanged:
            if mods.isEmpty {
                // Все модификаторы отпущены — если что-то держали, это и есть
                // хоткей «только модификатор».
                if !pendingModifiers.isEmpty {
                    finalize(tag: tag, hotkey: Hotkey(keyCode: nil, modifiers: pendingModifiers))
                }
            } else {
                pendingModifiers.formUnion(mods)
            }
        default:
            break
        }
    }

    private func finalize(tag: Int, hotkey: Hotkey) {
        let dictation = tag == 2 ? hotkey : config.config.dictationHotkey
        let convert = tag == 0 ? hotkey : config.config.convertHotkey
        let toggle = tag == 1 ? hotkey : config.config.toggleAutoHotkey
        if let error = dictation.dictationValidationError(convert: convert, toggleAuto: toggle) {
            stopRecording()
            errorLabel.stringValue = error
            refreshValues()
            return
        }
        config.update {
            if tag == 0 { $0.convertHotkey = hotkey }
            else if tag == 1 { $0.toggleAutoHotkey = hotkey }
            else { $0.dictationHotkey = hotkey }
        }
        stopRecording()
        refreshValues()
    }

    private func stopRecording() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        onRecordingChanged?(false)
        recordingTag = nil
        pendingModifiers = []
        for (t, b) in recordButtons {
            b.isEnabled = true
            b.title = "Записать"
            _ = t
        }
    }

    @objc private func resetRow(_ sender: NSButton) {
        if monitor != nil { stopRecording() }
        if sender.tag == 1 {
            config.update { $0.toggleAutoHotkey = nil }
            errorLabel.stringValue = ""
            refreshValues()
        } else {
            finalize(tag: sender.tag, hotkey: sender.tag == 0 ? .defaultConvert : .defaultDictation)
        }
    }

    // MARK: - NSWindowDelegate

    public func windowWillClose(_ notification: Notification) {
        cancelRecording()
    }

    public func windowDidResignKey(_ notification: Notification) {
        cancelRecording()
    }

    /// A local monitor cannot finish a chord after focus leaves this window.
    /// Release Engine's recording gate without saving any partial modifiers.
    @objc private func cancelRecording() {
        guard recordingTag != nil else { return }
        stopRecording()
        refreshValues()
    }

    // MARK: - Модификаторы NSEvent → модель

    /// Обобщённый набор модификаторов (без различия левый/правый), симметрично
    /// `Engine.modifierSet(from:)` — так записанный хоткей потом совпадёт.
    private static func modifiers(from flags: NSEvent.ModifierFlags) -> Set<Hotkey.Modifier> {
        let m = flags.intersection(.deviceIndependentFlagsMask)
        var out: Set<Hotkey.Modifier> = []
        if m.contains(.command) { out.insert(.command) }
        if m.contains(.option) { out.insert(.option) }
        if m.contains(.control) { out.insert(.control) }
        if m.contains(.shift) { out.insert(.shift) }
        if m.contains(.capsLock) { out.insert(.capsLock) }
        if m.contains(.function) { out.insert(.function) }
        return out
    }
}
#endif
