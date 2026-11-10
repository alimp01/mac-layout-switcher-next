// Системный слой macOS. Весь файл — под #if os(macOS): на Linux target
// собирается в пустой executable, чтобы `swift build`/`swift test` были зелёными.
#if os(macOS)
import Foundation
import CoreGraphics
import AppKit
import SwitcherCore

/// Translates the event tap into core decisions. Fresh tracked words use a
/// cancellable Backspace/Unicode batch even without AX; its result is event
/// submission, not editor readback. Selected/preexisting text and dictation
/// retain exact AX source/selection checks and confirmed replacement results.
/// Physical input shares Typist's serial queue, with native separator flags.
public final class Engine {

    private let core: EngineCore
    private let detector: Detector
    private let snippets: SnippetStore
    private let typist: Typist
    private let config: Config
    private let tap = EventTap()
    private let inputFocus = InputFocusGuard()
    private let environment = KeyboardEnvironment()
    private var physicalFlags: CGEventFlags = []
    private let selectionConverter = SelectionConverter()
    private lazy var conversionNotice = ConversionNotice()
    private var queuedNavigation = false
    private var trackedBatch: TrackedInputBatch?
    private var inputApplicationPID: pid_t?
    private var inputSequence: UInt64 = 0
    let dictation = DictationCoordinator()
    private var dictationGesture = DictationGesture()
    private var dictationRequested = false
    private var suppressedKeyUps: Set<UInt16> = []
    private var shortcutKeysDown: Set<UInt16> = []
    private var waitForRecorderModifiersUp = false
    var isRecordingHotkey = false {
        didSet {
            resetPhysicalInputState()
            inputFocus.invalidate()
            if isRecordingHotkey {
                dictation.cancel()
                _ = core.handle(.reset)
            } else {
                waitForRecorderModifiersUp = true
            }
        }
    }

    /// Озвучка ввода (истории G02/G10). Инжектится из `main` после создания
    /// Engine; nil → работаем молча. Звучат только исправление и откат
    /// (см. `playSound(for:)`) — на обычные нажатия звука нет.
    public var sounds: Sounds?

    /// Вызывается, когда автопереключение поменялось хоткеем `.toggleAuto` —
    /// `main` обновляет галочку в меню. Аргумент — новое состояние.
    public var onAutoSwitchChanged: ((Bool) -> Void)?

    /// Вызывается после каждого programmatic `LayoutSwitcher.select` (авто-
    /// исправление, Option-конвертация, откат) — `main` обновляет индикатор
    /// раскладки в меню-баре, не дожидаясь системного уведомления. Может прийти
    /// не с главного потока — получатель сам уходит на main.
    public var onLayoutSwitched: ((Lang) -> Void)?

    /// Виртуальный код Backspace (kVK_Delete).
    private static let backspaceKeyCode: UInt16 = 51

    /// Разделители слова. Пунктуация намеренно НЕ здесь: клавиши `;,.[]` в
    /// EN-раскладке дают буквы ЙЦУКЕН внутри слова (cgfcb,j = спасибо), и
    /// детектор рассчитывает видеть их как часть слова. Граница — только пробелы.
    private static let boundaryChars: Set<Character> = [" ", "\t", "\n", "\r"]

    // Детекция «чистого» тапа модификатора(ов) — обобщение прежней логики
    // одиночного Option на любой сконфигурированный модификатор-хоткей.
    // `peak` — максимальный набор модификаторов за текущий жест удержания;
    // `dirty` — во время жеста была нажата обычная клавиша (жест уже не «чистый
    // тап», это набор текста/комбинация).
    private var modifierGesturePeak: Set<Hotkey.Modifier> = []
    private var modifierGestureDirty = false

    /// Счётчики отмен per-word (spec G03). Загружаются из undo-counts.json при
    /// старте, обновляются по `EngineOutcome.undoCountUpdate` и сохраняются.
    private var undoCounts: [String: Int]

    public init(config: Config = Config()) {
        self.config = config
        config.load()

        let detector = Detector()
        detector.load(from: config.exclusionsURL)
        let snippets = SnippetStore()
        snippets.load(from: config.snippetsURL)

        self.detector = detector
        self.snippets = snippets
        self.typist = Typist()

        let undoCounts = config.loadUndoCounts()
        self.undoCounts = undoCounts
        // separatorAlreadyTyped: false — активный tap перехватывает разделитель
        // до доставки, ядро просит дослать его после перепечатки.
        self.core = EngineCore(
            detector: detector,
            snippets: snippets,
            autoSwitch: config.config.autoSwitch,
            undoThreshold: config.config.undoThreshold,
            undoCounts: undoCounts,
            separatorAlreadyTyped: false)
        environment.onChange = { [weak self] in self?.inputFocus.invalidate() }
        inputFocus.onChange = { [weak self] in
            self?.selectionConverter.cancel()
            self?.core.resetTrackingPreservingCaretJump()
            self?.queuedNavigation = false
        }
        typist.onWithheldInput = { [weak self] text in self?.conversionNotice.appendWithheldInput(text) }
        typist.onUnconfirmedReplacement = { [weak self] original, replacement in
            self?.conversionNotice.retainReplacement(original: original, replacement: replacement)
        }
        inputFocus.shouldSample = { [weak self] in self?.typist.isBusy == false && self?.selectionConverter.isPending == false }
        typist.onIdle = { [weak self] in
            guard let self, !self.typist.isBusy else { return }
            self.trackedBatch = nil
            if self.queuedNavigation { self.inputFocus.invalidate() }
            else { self.inputFocus.finishBatch() }
        }
        dictation.shortcutName = { [weak config] in config?.config.dictationHotkey.displayName ?? "" }
        dictation.onInsert = { [weak self] text, target, permit, completion in
            guard let self else { completion(.fallback(.changed)); return }
            self.inputFocus.invalidate()
            self.typist.insertDictation(text, target: target, permit: permit) { [weak self] remaining in
                _ = self?.core.handle(.reset)
                completion(remaining)
            }
        }
    }

    /// Включает перехват. `false` — система отказала (нет разрешений).
    @discardableResult
    public func start() -> Bool {
        resetPhysicalInputState()
        KeyTranslator.start()
        Typist.warmUp()
        environment.start()
        let started = tap.start { [weak self] stroke in
            self?.handle(keyEvent: stroke) ?? .pass
        }
        guard started else {
            stop()
            return false
        }
        dictation.paused = false
        inputFocus.start()
        return true
    }

    /// Останавливает перехват.
    public func stop() {
        dictation.paused = true
        dictation.cancel()
        resetPhysicalInputState()
        _ = core.handle(.reset)
        tap.stop()
        environment.stop()
        inputFocus.stop()
    }

    /// Tap suspension and shortcut recording can hide any corresponding key-up.
    /// No ownership or modifier-tap state may survive those boundaries.
    private func resetPhysicalInputState() {
        selectionConverter.cancel()
        dictationGesture.reset()
        dictationRequested = false
        suppressedKeyUps.removeAll()
        shortcutKeysDown.removeAll()
        modifierGesturePeak = []
        modifierGestureDirty = false
        waitForRecorderModifiersUp = false
    }

    /// Глобальный тумблер автоисправления (пункт меню). Option-хоткей и сниппеты
    /// продолжают работать при `false`.
    public func setAutoSwitch(_ on: Bool) {
        core.autoSwitch = on
        config.update { $0.autoSwitch = on }
    }

    /// Перечитывает config/snippets/exclusions с диска (после ручной правки
    /// JSON из меню).
    public func reload() {
        config.load()
        detector.load(from: config.exclusionsURL)
        snippets.load(from: config.snippetsURL)
        core.autoSwitch = config.config.autoSwitch
    }

    // MARK: - Приём события от tap

    /// Транслирует один `KeyStroke` в события ядра, исполняет команды и
    /// возвращает решение активному tap'у. Подавляет пары обычных хоткеев,
    /// исправляемые разделители и ввод для последовательного переигрывания.
    /// Вызывается в колбэке tap'а, на
    /// главном потоке: никакого I/O и sleep здесь — решение ядра это детектор
    /// на одном слове, тяжёлая работа уходит на очередь `Typist`.
    @discardableResult
    public func handle(keyEvent stroke: KeyStroke) -> TapDecision {
        physicalFlags = stroke.flags
        if stroke.kind != .keyUp { inputSequence &+= 1 }
        if stroke.kind == .tapInterrupted {
            // Unlike a click, suspension can hide releases. Retire ownership
            // synchronously before the tap accepts any fresh physical input.
            dictation.invalidateInsertion()
            // A missed release must not leave recording running. A session
            // already released can still finish into its existing recovery UI.
            if dictationRequested {
                DispatchQueue.main.async { [weak self] in self?.dictation.cancel() }
            }
            resetPhysicalInputState()
            inputFocus.invalidate()
            return .pass
        }
        // Consumed shortcuts own their repeats as well as their key-up, even
        // if the user releases a modifier before releasing the ordinary key.
        if stroke.kind == .keyDown, shortcutKeysDown.contains(stroke.keyCode) {
            dictation.invalidateInsertion()
            return .suppress
        }
        if stroke.kind == .keyDown, selectionConverter.cancel() {
            // Provisional manual undo/word state must not contaminate new input.
            _ = core.handle(.reset)
        }
        if stroke.kind == .contextChanged {
            dictation.invalidateInsertion()
            inputApplicationPID = environment.pid
            inputFocus.invalidate()
            _ = core.handle(.caretJump)
            modifierGestureDirty = true
            return .pass
        }
        // Dictation is explicitly requested even in auto-excluded editors.
        // The event callback only tracks keys and schedules work on main.
        let secure = environment.secure
        let currentPID = environment.pid
        if currentPID != inputApplicationPID {
            inputApplicationPID = currentPID
            inputFocus.invalidate()
        }
        core.isPaused = secure || inputFocus.isProtectedField || isExcludedApp()
        if core.isPaused { inputFocus.invalidate() }
        if stroke.kind == .keyUp {
            shortcutKeysDown.remove(stroke.keyCode)
            if suppressedKeyUps.remove(stroke.keyCode) != nil { return .suppress }
        }
        if isRecordingHotkey {
            modifierGesturePeak = []
            modifierGestureDirty = true
            return .pass
        }
        if waitForRecorderModifiersUp {
            if modifierSet(from: stroke.flags).isEmpty { waitForRecorderModifiersUp = false }
            modifierGesturePeak = []
            modifierGestureDirty = true
            if stroke.kind != .keyDown || waitForRecorderModifiersUp { return .pass }
        }
        if stroke.kind == .keyDown, stroke.keyCode == 53, dictationRequested || dictation.isActive {
            dictationRequested = false
            dictation.invalidateInsertion()
            dictationGesture.cancelHold()
            suppressedKeyUps.insert(stroke.keyCode)
            DispatchQueue.main.async { [weak self] in self?.dictation.cancel() }
            _ = core.handle(.reset)
            return .suppress
        }
        let modifiers = modifierSet(from: stroke.flags)
        let gestureEvent: DictationGesture.Event
        switch stroke.kind {
        case .keyDown: gestureEvent = .down(stroke.keyCode, repeatKey: stroke.isAutorepeat)
        case .keyUp: gestureEvent = .up(stroke.keyCode)
        case .flagsChanged, .contextChanged, .tapInterrupted: gestureEvent = .modifiers
        }
        let chosen = config.config.dictationHotkey
        let valid = chosen.dictationValidationError(convert: config.config.convertHotkey,
                                                     toggleAuto: config.config.toggleAutoHotkey) == nil
        let action = dictationGesture.handle(gestureEvent, modifiers: modifiers,
                                             hotkey: !secure && valid ? chosen : nil)
        switch action {
        case .begin:
            modifierGesturePeak.formUnion(modifiers)
            modifierGestureDirty = true
            dictationRequested = true
            dictation.armInsertion()
            _ = core.handle(.reset)
            DispatchQueue.main.async { [weak self] in self?.dictation.hold() }
            return stroke.kind == .keyDown ? .suppress : .pass
        case .end, .endPassingEvent:
            modifierGestureDirty = true
            dictationRequested = false
            DispatchQueue.main.async { [weak self] in self?.dictation.release() }
            // An unrelated key that happens to reveal released modifiers must
            // retain its ordinary behavior. Only the consumed key-up is hidden.
            if action == .end { return .suppress }
            if stroke.kind == .flagsChanged { return .pass }
        case .consume: return .suppress
        case .pass: break
        }
        // Hotkey repeats/releases were consumed above. Any other key-down is
        // intervention even while ASR is running; returning to the same field
        // never revives this session's permission.
        if stroke.kind == .keyDown { dictation.invalidateInsertion() }
        if secure { dictation.invalidateInsertion() }
        if secure, dictation.isActive {
            DispatchQueue.main.async { [weak self] in self?.dictation.cancel() }
        }
        if dictation.isInserting, !secure {
            // No layout correction can race speech insertion. Physical keys
            // replay behind it, through the same serial Typist queue.
            _ = core.handle(.reset)
            if stroke.kind == .keyDown,
               let replay = Self.replayPress(for: stroke, events: translate(stroke)) {
                modifierGestureDirty = true
                suppressedKeyUps.insert(stroke.keyCode)
                typist.send(replay, ticket: inputFocus.ticket)
                return .suppress
            }
            return .pass
        }

        switch stroke.kind {
        case .contextChanged, .tapInterrupted: return .pass
        case .keyUp:
            return .pass
        case .flagsChanged:
            if let event = modifierTapEvent(for: stroke) {
                dispatch(event)
            }
            return .pass
        case .keyDown:
            // Любая печатная/командная клавиша рвёт «чистый» тап модификатора.
            modifierGestureDirty = true
            // Consume the full ordinary-key shortcut pair, including repeats.
            if let event = hotkeyEvent(
                keyCode: stroke.keyCode, modifiers: modifierSet(from: stroke.flags)) {
                shortcutKeysDown.insert(stroke.keyCode)
                suppressedKeyUps.insert(stroke.keyCode)
                if !stroke.isAutorepeat { dispatch(event) }
                return .suppress
            }
            let events = translate(stroke)
            // A repeat can arrive while AX has temporarily selected the source.
            // Letting it pass would replace that source with the repeated key
            // before the worker can write. Reset word decisions, but keep the
            // active replacement and serialize the actual text-editing input.
            if typist.isBusy, trackedBatch?.permit.isAllowed == true || inputFocus.ticket != nil,
               let event = Self.textEditingRepeat(for: stroke),
               let replay = Self.replayPress(for: stroke, events: [event]) {
                _ = core.handle(.reset)
                let navigates = Self.isNavigationBoundary(event)
                replayPhysical(replay, navigates: navigates)
                if navigates { queuedNavigation = true }
                suppressedKeyUps.insert(stroke.keyCode)
                return .suppress
            }
            if events.contains(.reset) {
                inputFocus.invalidate()
                _ = core.handle(.caretJump)
                return .pass
            }

            // Гонка ввода: перепечатка ещё идёт. Нажатие переигрывается той же
            // очередью ПОСЛЕ синтетики; ядро получает его прямо сейчас, чтобы
            // порядок решений совпадал с порядком доставки. Не смогли создать
            // событие для переигрывания — ведём себя как в спокойном режиме.
            if typist.isBusy, trackedBatch?.permit.isAllowed == true || inputFocus.ticket != nil, let replay = Self.replayPress(for: stroke, events: events) {
                let navigates = events.contains(where: Self.isNavigationBoundary)
                if queuedNavigation {
                    _ = core.handle(.reset)
                    replayPhysical(replay, navigates: navigates)
                    suppressedKeyUps.insert(stroke.keyCode)
                    return .suppress
                }
                var consumed = false
                for event in events {
                    // Разделитель на границе: если ядро исправляет слово, execute
                    // поставит перепечатку и затем этот же `replay` как досылку.
                    if dispatch(event, stroke: stroke, prepared: replay) == .suppress {
                        consumed = true
                    }
                }
                if !consumed {
                    replayPhysical(replay, navigates: navigates)
                }
                if navigates { queuedNavigation = true }
                suppressedKeyUps.insert(stroke.keyCode)
                return .suppress
            }

            var decision = TapDecision.pass
            for event in events {
                if dispatch(event, stroke: stroke) == .suppress {
                    decision = .suppress
                }
            }
            if events.contains(where: Self.isNavigationBoundary) {
                if decision == .pass { inputFocus.invalidate() }
                else { queuedNavigation = true }
            }
            if decision == .suppress { suppressedKeyUps.insert(stroke.keyCode) }
            return decision
        }
    }

    private func replayPhysical(_ press: Typist.KeyPress, navigates: Bool) {
        if let batch = trackedBatch, batch.permit.isAllowed { typist.send(press, batch: batch) }
        else { typist.send(press, ticket: inputFocus.ticket, navigates: navigates) }
    }

    private static func isNavigationBoundary(_ event: InputEvent) -> Bool {
        if case .boundary(let separator) = event { return separator != " " }
        return false
    }

    /// Repeats never grow the decision buffer. Only text editing is queued;
    /// commands, cursor movement and other navigation still cancel ownership.
    private static func textEditingRepeat(for stroke: KeyStroke) -> InputEvent? {
        guard stroke.isAutorepeat, !stroke.flags.contains(.maskCommand),
              !stroke.flags.contains(.maskControl) else { return nil }
        if stroke.keyCode == backspaceKeyCode { return .backspace }
        guard stroke.characters.count == 1, let character = stroke.characters.first else { return nil }
        if boundaryChars.contains(character) { return .boundary(character) }
        guard !character.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        return .char(character)
    }

    /// Событие для переигрывания нажатия, попавшего в окно перепечатки.
    /// Одиночная буква — юникодом (ядро уже получило именно этот символ, и
    /// приложение получит его же, какая бы раскладка ни была активна к моменту
    /// доставки); всё остальное (разделители, Backspace, стрелки, Cmd-комбинации)
    /// — тем же keyCode и флагами, что нажал пользователь.
    private static func replayPress(for stroke: KeyStroke, events: [InputEvent]) -> Typist.KeyPress? {
        if events.count == 1, case .char(let ch) = events[0] {
            return Typist.makeUnicodePress(ch)
        }
        return Typist.makeKeyPress(keyCode: CGKeyCode(stroke.keyCode), flags: stroke.flags)
    }

    /// Прогоняет одно событие через ядро и исполняет команду; для `.toggleAuto`
    /// дополнительно персистит config (асинхронно) и уведомляет UI. `stroke` —
    /// исходное нажатие (keyCode/флаги для досылки разделителя), `prepared` —
    /// уже созданное событие досылки, если оно есть. Возвращает `.suppress`,
    /// если исходное нажатие доставлять нельзя (разделитель будет дослан
    /// после перепечатки).
    @discardableResult
    private func dispatch(
        _ event: InputEvent, stroke: KeyStroke? = nil, prepared: Typist.KeyPress? = nil
    ) -> TapDecision {
        if event == .hotkey(.convert) {
            let generation = inputFocus.generation
            let sequence = inputSequence
            DispatchQueue.main.async { [weak self] in
                guard let self, generation.isAllowed, self.inputSequence == sequence else { return }
                self.requestConversion()
            }
            return .pass
        }
        let outcome = core.handle(event)
        let decision = execute(outcome, stroke: stroke, prepared: prepared)
        if case .char = event { scheduleLiveCorrection() }
        if case .hotkey(.toggleAuto) = event {
            config.update { $0.autoSwitch = core.autoSwitch }
            onAutoSwitchChanged?(core.autoSwitch)
        }
        return decision
    }

    private func scheduleLiveCorrection() {
        let sequence = inputSequence
        let generation = inputFocus.generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, generation.isAllowed, self.inputSequence == sequence,
                  !self.typist.isBusy, !self.selectionConverter.isPending,
                  !self.environment.secure, !self.inputFocus.isProtectedField, !self.environment.chromium, !self.isRecordingHotkey,
                  !self.dictation.isActive, !self.dictationRequested,
                  self.physicalFlags.intersection([.maskShift, .maskAlternate, .maskCommand, .maskControl]).isEmpty else { return }
            self.execute(self.core.liveCorrection())
        }
    }

    /// Explicit layout switching does not read or mutate editor text.
    private func toggleLayout() {
        guard let current = LayoutSwitcher.current() else {
            conversionNotice.show(message: "Не удалось определить раскладку. Включите русскую и английскую раскладки в настройках macOS.")
            return
        }
        let next: Lang = current == .ru ? .en : .ru
        if LayoutSwitcher.select(next) { KeyTranslator.refresh(); onLayoutSwitched?(next) }
        else { conversionNotice.show(message: "Не удалось переключить раскладку. Включите русскую и английскую раскладки в настройках macOS.") }
    }

    private func requestConversion() {
        guard !typist.isBusy, !dictation.isActive, !dictationRequested else { return }
        // Explicit source switching does not need access to editor contents.
        if core.isPaused { toggleLayout(); return }
        let generation = inputFocus.generation
        let expected = inputFocus.ticket?.target
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        selectionConverter.capture(expectedPID: pid) { [weak self] captured, permit in
            guard let self, permit.isAllowed, generation.isAllowed else { return }
            self.conversionNotice.hide()
            switch captured {
            case .unavailable(let reason):
                self.selectionConverter.finish(permit)
                // Missing AX is not a veto for a fresh physical-key stream.
                // Protected/changed destinations still revoke that authority.
                switch reason {
                case .protectedField, .secureInput, .changed, .unavailableApplication, .selectionTooLarge, .unreadableSelection:
                    break
                default:
                    let outcome = self.core.handle(.hotkey(.convert))
                    if outcome.command != .none {
                        self.execute(outcome)
                        return
                    }
                }
                _ = self.core.handle(.reset)
                self.toggleLayout()
                self.conversionNotice.show(message: "Текст не изменён: \(reason.message)")
            case .empty(let target, let range, let word, let value):
                guard let ticket = self.inputFocus.bind(target, generation: generation, replacingCachedTarget: true), !self.typist.isBusy else {
                    self.selectionConverter.finish(permit)
                    _ = self.core.handle(.reset)
                    return
                }
                // A first AX capture adds a guard to the observed stream. Only a
                // positively different cached field revokes that stream.
                if let expected, !expected.matches(target) { _ = self.core.handle(.reset) }
                let outcome = self.core.handle(.hotkey(.convert))
                if outcome.command == .none {
                    if let word, KeyMap.selectionConversion(word.text).text != word.text {
                        self.replaceSelection(word, permit: permit, ticket: ticket)
                    } else {
                        self.selectionConverter.finish(permit)
                        self.toggleLayout()
                    }
                } else { self.execute(outcome, conversionPermit: permit, conversionSelection: range, conversionValue: value) }
            case .selected(let selection):
                guard let ticket = self.inputFocus.bind(selection.target, generation: generation, replacingCachedTarget: true) else {
                    self.selectionConverter.finish(permit)
                    return
                }
                self.replaceSelection(selection, permit: permit, ticket: ticket)
            }
        }
    }

    private func replaceSelection(_ selection: SelectionConverter.Selection, permit: InputFocusGuard.Permit,
                                  ticket: InputFocusGuard.Ticket) {
        _ = core.handle(.reset)
        selectionConverter.replace(selection, permit: permit, typist: typist, replayRoute: ticket.replayRoute,
            failure: { [weak self] reason in
                guard permit.isAllowed else { return }
                self?.conversionNotice.show(message: "Текст не изменён: \(reason.message)")
            }) { [weak self] result, language in
            guard let self else { return }
            self.selectionConverter.finish(permit)
            if result.isUncertain { return }
            guard permit.isAllowed else { return }
            _ = self.core.handle(.reset)
            if result == .confirmed {
                LayoutSwitcher.select(language)
                KeyTranslator.refresh()
                self.onLayoutSwitched?(language)
                self.sounds?.playCorrection()
            }
        }
    }

    /// Звук по итогу события: откат авто-исправления (в исключения ушло слово) —
    /// сигнал отката; любая другая замена (авто-исправление, конвертация по
    /// Option, разворот сниппета) — сигнал исправления. На обычные нажатия
    /// звука нет (G10); пауза гейтится сама собой: на паузе ядро не выдаёт
    /// `replaceLast`, значит и звучать нечему.
    private func playSound(for outcome: EngineOutcome) {
        guard case .replaceLast = outcome.command else { return }
        if outcome.excludedWordToPersist != nil {
            sounds?.playUndo()
        } else {
            sounds?.playCorrection()
        }
    }

    // MARK: - Трансляция keyDown → события ядра

    private func translate(_ stroke: KeyStroke) -> [InputEvent] {
        // Cmd/Ctrl-комбинация — команда приложения, не набор: сброс буфера.
        if stroke.flags.contains(.maskCommand) || stroke.flags.contains(.maskControl) {
            return [.reset]
        }
        // Автоповтор удержания не должен наращивать «слово».
        if stroke.isAutorepeat {
            return [.reset]
        }
        if stroke.keyCode == Self.backspaceKeyCode {
            return [.backspace]
        }
        // UCKeyTranslate can return C0 controls for arrows, Escape and F-keys.
        // Only printable text and explicit editing boundaries belong to us.
        guard stroke.characters.count == 1, let ch = stroke.characters.first else {
            return [.reset]
        }
        if Self.boundaryChars.contains(ch) {
            return [.boundary(ch)]
        }
        guard !ch.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            return [.reset]
        }
        return [.char(ch)]
    }

    // MARK: - Детекция тапа модификатора(ов) и сопоставление с хоткеем

    /// Собирает набор модификаторов из CGEventFlags. Левый и правый вариант
    /// одной клавиши намеренно НЕ различаются (обе Option → `.option`): так
    /// дефолтный хоткей `[.option]` срабатывает и на левый, и на правый Option,
    /// сохраняя прежнее поведение. Правые `Modifier`-кейсы существуют в модели,
    /// но окно-рекордер и Engine пишут/читают обобщённые модификаторы.
    private func modifierSet(from flags: CGEventFlags) -> Set<Hotkey.Modifier> {
        var mods: Set<Hotkey.Modifier> = []
        if flags.contains(.maskCommand) { mods.insert(.command) }
        if flags.contains(.maskAlternate) { mods.insert(.option) }
        if flags.contains(.maskControl) { mods.insert(.control) }
        if flags.contains(.maskShift) { mods.insert(.shift) }
        if flags.contains(.maskAlphaShift) { mods.insert(.capsLock) }
        if flags.contains(.maskSecondaryFn) { mods.insert(.function) }
        return mods
    }

    /// Одиночный/составной тап модификаторов без промежуточных обычных клавиш →
    /// событие соответствующего хоткея. Жест начинается, когда модификаторы
    /// появляются, и завершается, когда все отпущены; `dirty` рвёт его при любой
    /// обычной клавише. Решение «этот тап = такой-то хоткей» принимает
    /// `Hotkey.matches` (keyCode: nil).
    private func modifierTapEvent(for stroke: KeyStroke) -> InputEvent? {
        let mods = modifierSet(from: stroke.flags)
        if mods.isEmpty {
            let peak = modifierGesturePeak
            let dirty = modifierGestureDirty
            modifierGesturePeak = []
            modifierGestureDirty = false
            guard !dirty, !peak.isEmpty else { return nil }
            return hotkeyEvent(keyCode: nil, modifiers: peak)
        } else {
            if modifierGesturePeak.isEmpty {
                modifierGesturePeak = mods
                modifierGestureDirty = false
            } else {
                modifierGesturePeak.formUnion(mods)
            }
            return nil
        }
    }

    /// Сопоставляет описание нажатия с настроенными хоткеями. Конвертация имеет
    /// приоритет над переключением авто (если пользователь назначил одно и то же
    /// — срабатывает конвертация).
    private func hotkeyEvent(
        keyCode: UInt16?, modifiers: Set<Hotkey.Modifier>) -> InputEvent? {
        if config.config.convertHotkey.matches(keyCode: keyCode, modifiers: modifiers) {
            return .hotkey(.convert)
        }
        if let toggle = config.config.toggleAutoHotkey,
           toggle.matches(keyCode: keyCode, modifiers: modifiers) {
            return .hotkey(.toggleAuto)
        }
        return nil
    }

    // MARK: - Исполнение команд

    /// Schedule fresh-buffer posting or guarded AX conversion. Suppress a
    /// separator only after its replay was constructed. A known interrupted
    /// mutation retains recovery text and cannot authorize dependent retries.
    @discardableResult
    private func execute(
        _ outcome: EngineOutcome, stroke: KeyStroke? = nil, prepared: Typist.KeyPress? = nil,
        conversionPermit: InputFocusGuard.Permit? = nil, conversionSelection: CFRange? = nil, conversionValue: String? = nil
    ) -> TapDecision {
        guard case .replaceLast(_, let text, let switchTo) = outcome.command else {
            if let conversionPermit { selectionConverter.finish(conversionPermit) }
            return .pass
        }
        if let expected = outcome.expectedText,
           let pid = inputApplicationPID, expected.count <= 65 {
            let separator: Typist.KeyPress?
            if let sep = outcome.reinjectSeparator {
                guard let press = prepared ?? separatorPress(stroke: stroke, sep: sep) else {
                    core.discardReplacement(outcome); return .pass
                }
                separator = press
            } else { separator = nil }
            let batch: TrackedInputBatch
            if let active = trackedBatch, active.permit === inputFocus.generation { batch = active }
            else { batch = TrackedInputBatch(permit: inputFocus.generation, applicationPID: pid); trackedBatch = batch }
            let source: InputFocusGuard.BufferedSource?
            if let conversionPermit {
                guard let ticket = inputFocus.ticket, let conversionSelection, let conversionValue else {
                    selectionConverter.finish(conversionPermit)
                    core.discardReplacement(outcome)
                    return .pass
                }
                source = InputFocusGuard.BufferedSource(target: ticket.target, selection: conversionSelection,
                                                        value: conversionValue, permit: conversionPermit)
            } else { source = nil }
            typist.replaceBuffered(expected: expected, with: text, batch: batch, separator: separator, source: source) { [weak self] result in
                guard let self else { return }
                if let conversionPermit { self.selectionConverter.finish(conversionPermit) }
                guard result == .posted else {
                    // Untouched cancellation may already track the next word.
                    // Interrupted posting withholds that input, so it cannot
                    // leave deletion authority for text never delivered.
                    let resetContext = batch.permit === self.inputFocus.generation
                        && (result == .interrupted || conversionPermit?.isAllowed != false)
                    self.core.discardReplacement(outcome, resetContext: resetContext)
                    if result == .untouched, conversionPermit?.isAllowed == true { self.conversionNotice.show() }
                    return
                }
                if batch.permit.isAllowed, conversionPermit?.isAllowed != false, let lang = switchTo {
                    LayoutSwitcher.select(lang)
                    KeyTranslator.refresh()
                    self.onLayoutSwitched?(lang)
                }
                self.playSound(for: outcome)
                if outcome.excludedWordToPersist != nil { self.config.saveExclusions(self.detector.exclusionList) }
                if let update = outcome.undoCountUpdate {
                    self.undoCounts[update.word.lowercased()] = update.count
                    self.config.saveUndoCounts(self.undoCounts)
                }
            }
            return separator == nil ? .pass : .suppress
        }
        guard let expected = outcome.expectedText, let ticket = inputFocus.ticket else {
            core.discardReplacement(outcome)
            if let conversionPermit {
                selectionConverter.finish(conversionPermit)
                if conversionPermit.isAllowed { conversionNotice.show() }
            }
            return .pass
        }
        let separator: Typist.KeyPress?
        if let sep = outcome.reinjectSeparator {
            guard let press = prepared ?? separatorPress(stroke: stroke, sep: sep) else {
                // Never run a delayed legacy replacement after a delivered Enter.
                core.discardReplacement(outcome)
                return .pass
            }
            separator = press
        } else { separator = nil }
        typist.replaceLastWord(expected: expected, with: text, ticket: ticket, separator: separator,
                               separatorCharacter: outcome.reinjectSeparator,
                               navigates: outcome.reinjectSeparator.map { $0 != " " } ?? false,
                               conversionPermit: conversionPermit, conversionSelection: conversionSelection, conversionValue: conversionValue) { [weak self] result in
            guard let self else { return }
            if let conversionPermit { self.selectionConverter.finish(conversionPermit) }
            guard result == .confirmed else {
                let rejected = self.inputFocus.reject(ticket)
                self.core.discardReplacement(outcome, resetContext: conversionPermit?.isAllowed != false && rejected)
                if !result.isUncertain, conversionPermit?.isAllowed == true { self.conversionNotice.show() }
                return
            }
            if ticket.permit.isAllowed, conversionPermit?.isAllowed != false, let lang = switchTo {
                LayoutSwitcher.select(lang)
                KeyTranslator.refresh()
                self.onLayoutSwitched?(lang)
            }
            self.playSound(for: outcome)
            if outcome.excludedWordToPersist != nil {
                self.config.saveExclusions(self.detector.exclusionList)
            }
            if let update = outcome.undoCountUpdate {
                self.undoCounts[update.word.lowercased()] = update.count
                self.config.saveUndoCounts(self.undoCounts)
            }
        }
        return separator == nil ? .pass : .suppress
    }

    /// Событие досылки разделителя: по реальному нажатию (keyCode + флаги),
    /// иначе по символу. `nil` — система отказала создать `CGEvent`.
    private func separatorPress(stroke: KeyStroke?, sep: Character) -> Typist.KeyPress? {
        if let stroke = stroke {
            return Typist.makeKeyPress(keyCode: CGKeyCode(stroke.keyCode), flags: stroke.flags)
        }
        guard let code = Typist.keyCode(forSeparator: sep) else { return nil }
        return Typist.makeKeyPress(keyCode: code, flags: [])
    }

    private func isExcludedApp() -> Bool {
        guard let bundle = environment.bundleID else { return false }
        return config.config.excludedApps.contains(bundle)
    }
}
#endif
