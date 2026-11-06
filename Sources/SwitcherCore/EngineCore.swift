import Foundation

/// Абстрактное входное событие платформонезависимого ядра решений.
/// macOS-`Engine` транслирует сюда CGEvent/`KeyStroke`; Linux-тесты подают
/// события напрямую — весь смысл в том, чтобы решение «что сделать» жило здесь.
public enum InputEvent: Equatable {
    /// Печатный символ, добавляемый к текущему слову.
    case char(Character)
    /// Backspace: убрать последний символ слова.
    case backspace
    /// Граница слова (пробел/таб/enter/…). `Character` — сам разделитель.
    /// В штатном режиме (`separatorAlreadyTyped == false`, активный tap) он
    /// ещё НЕ доставлен приложению: если слово исправляется, исполнитель
    /// обязан подавить нажатие и дослать разделитель после перепечатки
    /// (`EngineOutcome.reinjectSeparator`). В legacy-режиме разделитель уже
    /// напечатан, и команда замены его сохраняет.
    case boundary(Character)
    /// Сработал сконфигурированный хоткей. macOS-`Engine` решает, что это за
    /// клавиша (через `Hotkey.matches`), и шлёт соответствующее действие.
    case hotkey(HotkeyAction)
    /// Сброс без исправления: комбинация с Cmd/Ctrl, автоповтор удержания,
    /// перемещение курсора (стрелки, мышь) — текущее слово больше не «наше».
    case reset
    /// Pointer/caret navigation; the first edited token may be only a fragment.
    case caretJump
}

/// Действие настраиваемого хоткея (таск 08). `convert` — прежнее поведение
/// одиночного Option: конвертация текущего/последнего слова или откат
/// авто-исправления в окне отмены. `toggleAuto` — вкл/выкл автопереключения.
public enum HotkeyAction: Equatable, Sendable {
    case convert
    case toggleAuto
}

/// Команда исполнителю. macOS-`Engine` переводит её в вызовы
/// `Typist`/`LayoutSwitcher`.
public enum EngineCommand: Equatable {
    /// Ничего не делать.
    case none
    /// Стереть `len` символов Backspace'ами и напечатать `text`; если `switchTo`
    /// задан — переключить системную раскладку. Если разделитель уже стоит в
    /// тексте (откат/конвертация завершённого слова, legacy-режим границы),
    /// он включён в `len`/`text`; если ещё не доставлен — его дошлёт
    /// исполнитель по `EngineOutcome.reinjectSeparator`.
    case replaceLast(len: Int, with: String, switchTo: Lang?)
}

/// Результат обработки события: команда + побочные факты для персиста.
public struct EngineOutcome: Equatable {
    /// Что должен сделать исполнитель.
    public let command: EngineCommand
    /// Exact observed source: AX executors validate it; buffered executors use
    /// its bounded character count without claiming editor readback.
    public let expectedText: String?
    /// Непусто, когда ядро добавило слово в исключения `Detector` (откат
    /// авто-исправления по Option достиг порога): `Engine` обязан сохранить
    /// exclusions.json.
    public let excludedWordToPersist: String?
    /// Непусто, когда откат изменил счётчик отмен слова (увеличил на 1 или
    /// сбросил в 0 при достижении порога): `Engine` обязан сохранить
    /// undo-counts.json. Ключ — исходное слово, регистр как пришёл.
    public let undoCountUpdate: (word: String, count: Int)?
    /// Непусто, когда ядро исправило слово на границе, а разделитель ещё не
    /// доставлен приложению (активный tap перехватил его до доставки):
    /// исполнитель обязан ПОДАВИТЬ исходное нажатие и напечатать этот
    /// разделитель строго ПОСЛЕ перепечатки слова. `nil` — разделитель
    /// (если он был) пропускается как есть, без задержки.
    public let reinjectSeparator: Character?

    public init(
        command: EngineCommand,
        expectedText: String? = nil,
        excludedWordToPersist: String? = nil,
        undoCountUpdate: (word: String, count: Int)? = nil,
        reinjectSeparator: Character? = nil
    ) {
        self.command = command
        self.expectedText = expectedText
        self.excludedWordToPersist = excludedWordToPersist
        self.undoCountUpdate = undoCountUpdate
        self.reinjectSeparator = reinjectSeparator
    }

    /// Пустой результат — событие ничего не меняет на экране.
    public static let none = EngineOutcome(command: .none)

    /// Ручной `==`: кортеж `undoCountUpdate` блокирует синтез Equatable.
    public static func == (lhs: EngineOutcome, rhs: EngineOutcome) -> Bool {
        guard lhs.command == rhs.command,
              lhs.expectedText == rhs.expectedText,
              lhs.excludedWordToPersist == rhs.excludedWordToPersist,
              lhs.reinjectSeparator == rhs.reinjectSeparator else { return false }
        switch (lhs.undoCountUpdate, rhs.undoCountUpdate) {
        case (nil, nil): return true
        case let (l?, r?): return l.word == r.word && l.count == r.count
        default: return false
        }
    }
}

/// Ядро логики переключателя: поток абстрактных событий → команды.
/// Платформонезависимо и детерминированно — вся склейка тестируется на Linux.
/// macOS-`Engine` лишь транслирует события и исполняет команды.
public final class EngineCore {

    private let buffer = WordBuffer()
    private var wordEdited = false
    private var liveApplied = false
    private var wordOverflowed = false
    private var manuallyCorrectedWord = false
    private var afterCaretJump = false
    private static let trackedWordLimit = 64
    private let detector: Detector
    private let snippets: SnippetStore
    private let now: () -> Double
    private let undoWindow: Double

    /// Порог отмен одной и той же замены, после которого слово уходит в
    /// исключения автоматически (spec G03, дефолт 3). `1` воспроизводит
    /// прежнее поведение — исключение с первого отката.
    private let undoThreshold: Int

    /// Счётчики отмен per-word (ключ — исходное слово в нижнем регистре,
    /// консистентно с `Detector.isExcluded`). Переживают перезапуск: приходят
    /// в `init` из undo-counts.json и отдаются наружу через `undoCountUpdate`.
    private var undoCounts: [String: Int]

    /// Режим границы слова. `false` (штатный, активный tap): разделитель на
    /// `.boundary` ещё не доставлен — исправление стирает только слово и
    /// просит исполнителя дослать разделитель (`reinjectSeparator`). `true`
    /// (legacy, listen-only tap, ADR 0004): разделитель уже напечатан —
    /// стирается и перепечатывается вместе со словом.
    private let separatorAlreadyTyped: Bool

    /// Глобальный тумблер автоисправления по детектору. `false` → детектор
    /// молчит, но Option-хоткей и сниппеты продолжают работать (см. spec).
    public var autoSwitch: Bool

    /// Автопауза: secure input или приложение-исключение. `true` → ядро молчит
    /// полностью и не буферизует (пароли и команды терминала не копим).
    public var isPaused: Bool = false {
        didSet {
            guard isPaused, !oldValue else { return }
            buffer.reset()
            wordEdited = false; liveApplied = false; wordOverflowed = false; manuallyCorrectedWord = false; afterCaretJump = false
            lastRegion = nil
            lastAuto = nil
            detector.resetContext()
        }
    }

    /// Последняя область у курсора, пригодная к ручной конвертации по Option:
    /// либо незавершённое слово в буфере (separator == ""), либо только что
    /// завершённое слово вместе с его разделителем.
    private struct Region {
        var word: String
        var separator: String
    }
    private var lastRegion: Region?

    /// Последнее АВТО-исправление — для отката по Option в окне `undoWindow`.
    private struct AutoCorrection {
        let original: String
        let corrected: String
        let separator: String
        /// Раскладка, которую надо вернуть при откате (была до исправления).
        let originalLang: Lang
        let time: Double
    }
    private var lastAuto: AutoCorrection?

    public init(
        detector: Detector,
        snippets: SnippetStore,
        autoSwitch: Bool = true,
        undoWindow: Double = 5,
        undoThreshold: Int = 3,
        undoCounts: [String: Int] = [:],
        separatorAlreadyTyped: Bool = false,
        now: @escaping () -> Double = { Date().timeIntervalSince1970 }
    ) {
        self.detector = detector
        self.snippets = snippets
        self.autoSwitch = autoSwitch
        self.undoWindow = undoWindow
        self.undoThreshold = undoThreshold
        self.separatorAlreadyTyped = separatorAlreadyTyped
        // Нормализуем ключи к нижнему регистру — сравнение без учёта регистра.
        self.undoCounts = Dictionary(
            undoCounts.map { ($0.key.lowercased(), $0.value) },
            uniquingKeysWith: { max($0, $1) })
        self.now = now
    }

    /// Обрабатывает одно событие и возвращает команду исполнителю.
    @discardableResult
    public func handle(_ event: InputEvent) -> EngineOutcome {
        // Переключение автопереключения — глобальная настройка, а не работа с
        // текстом: срабатывает даже на автопаузе (secure input / приложение-
        // исключение), где ядро иначе молчит.
        if case .hotkey(.toggleAuto) = event {
            autoSwitch.toggle()
            return .none
        }

        if event == .reset || event == .caretJump {
            wordEdited = false; liveApplied = false; wordOverflowed = false; manuallyCorrectedWord = false; afterCaretJump = false
            buffer.reset()
            afterCaretJump = event == .caretJump
            lastAuto = nil
            lastRegion = nil
            detector.resetContext()
            return .none
        }
        if isPaused { return .none }

        switch event {
        case .char(let c):
            guard !wordOverflowed else { return .none }
            guard buffer.word.count < Self.trackedWordLimit else {
                _ = handle(.reset); wordOverflowed = true; return .none
            }
            buffer.append(char: c)
            // Печать после исправления закрывает окно отката и начинает новое
            // слово — прошлая завершённая область больше не «последняя».
            lastAuto = nil
            lastRegion = nil
            return .none

        case .backspace:
            wordEdited = true
            if wordOverflowed { return .none }
            if buffer.word.isEmpty {
                let jumped = afterCaretJump
                _ = handle(.reset)
                afterCaretJump = jumped
                wordEdited = true
                return .none
            }
            lastRegion = nil
            buffer.backspace()
            lastAuto = nil
            return .none

        case .reset, .caretJump:
            return .none // Handled above, including while paused.

        case .boundary(let sep):
            // Return may submit; Tab may move focus. Neither leaves an undo
            // candidate or language context for the next input location.
            defer { if sep != " " { _ = handle(.reset) } }
            return handleBoundary(sep)

        case .hotkey(.convert):
            return handleConvert()

        case .hotkey(.toggleAuto):
            // Обработано выше, до guard isPaused; сюда не доходит.
            return .none
        }
    }

    /// A technical focus/environment refresh invalidates text authority but
    /// must not erase the one-shot fragment guard established by a user click.
    public func resetTrackingPreservingCaretJump() {
        let jumped = afterCaretJump
        let edited = wordEdited
        _ = handle(.reset)
        afterCaretJump = jumped
        wordEdited = jumped && edited
    }

    /// Executors call this when a proposed replacement was not completed.
    /// Undo teaching is provisional until the corresponding text really moved.
    public func discardReplacement(_ outcome: EngineOutcome, resetContext: Bool = true) {
        if let word = outcome.excludedWordToPersist { detector.removeExclusion(word) }
        if let update = outcome.undoCountUpdate {
            undoCounts[update.word.lowercased()] = update.count == 0 ? undoThreshold - 1 : max(0, update.count - 1)
        }
        if resetContext { _ = handle(.reset) }
    }

    /// Quiet-time high-confidence decision. The platform enforces context,
    /// app-family, modifier and queue gates before requesting this proposal.
    public func liveCorrection() -> EngineOutcome {
        let word = buffer.word
        guard autoSwitch, !isPaused, !wordEdited, !liveApplied, !wordOverflowed, !manuallyCorrectedWord,
              (4...16).contains(word.count), !snippets.hasTrigger(startingWith: word) else { return .none }
        let language: Lang
        switch detector.liveVerdict(for: word) {
        case .ru: language = .ru
        case .en: language = .en
        case .unsure: return .none
        }
        guard let converted = detector.liveConvertedText(for: word, to: language), converted != word else { return .none }
        setBuffer(to: converted)
        liveApplied = true
        lastAuto = AutoCorrection(original: word, corrected: converted, separator: "",
            originalLang: language == .ru ? .en : .ru, time: now())
        return EngineOutcome(command: .replaceLast(len: word.count, with: converted, switchTo: language), expectedText: word)
    }

    // MARK: - Граница слова

    private func handleBoundary(_ sep: Character) -> EngineOutcome {
        let word = buffer.word
        let liveUndo = liveApplied ? lastAuto : nil
        let protectWord = manuallyCorrectedWord
        // Pinned Keyboop's unknown-AX rule: a single letter after a jump is
        // protected when Backspace preceded it; otherwise a fresh start is allowed.
        let guardFragment = afterCaretJump && (word.count != 1 || wordEdited)
        wordEdited = false; liveApplied = false; wordOverflowed = false; manuallyCorrectedWord = false; afterCaretJump = false
        buffer.boundary()
        lastAuto = nil
        if let auto = liveUndo, auto.corrected == word {
            _ = detector.verdict(for: word)
            lastRegion = Region(word: word, separator: String(sep))
            lastAuto = AutoCorrection(original: auto.original, corrected: word, separator: String(sep),
                originalLang: auto.originalLang, time: auto.time)
            return .none
        }

        guard !word.isEmpty else {
            lastRegion = nil
            return .none
        }
        let sepStr = String(sep)

        // 1) Сниппеты — приоритет выше детектора; после разворота детектор
        //    к этому слову не применяется.
        if let expansion = snippets.expansion(for: word) {
            lastRegion = Region(word: expansion, separator: sepStr)
            return boundaryReplace(original: word, with: expansion, sep: sep, switchTo: nil)
        }

        if protectWord {
            lastRegion = Region(word: word, separator: sepStr)
            return .none
        }

        // 2) Автоисправление по детектору (если глобально включено).
        if autoSwitch {
            switch detector.verdict(for: word, afterCaretJump: guardFragment) {
            case .ru: return autoCorrect(word: word, sep: sepStr, to: .ru)
            case .en: return autoCorrect(word: word, sep: sepStr, to: .en)
            case .unsure: break
            }
        }

        // 3) Ничего не исправляем, но слово остаётся кандидатом на ручную
        //    конвертацию по Option.
        lastRegion = Region(word: word, separator: sepStr)
        return .none
    }

    private func autoCorrect(word: String, sep: String, to lang: Lang) -> EngineOutcome {
        let converted = detector.convertedText(for: word, to: lang)
        let originalLang: Lang = (lang == .ru) ? .en : .ru
        lastRegion = Region(word: converted, separator: sep)
        // Для отката запоминаем разделитель: к моменту хоткея он уже стоит в
        // тексте в обоих режимах (в штатном — его дослал исполнитель).
        lastAuto = AutoCorrection(
            original: word, corrected: converted, separator: sep,
            originalLang: originalLang, time: now())
        return boundaryReplace(original: word, with: converted, sep: Character(sep), switchTo: lang)
    }

    /// Команда замены слова на границе с учётом режима разделителя.
    /// Штатно разделитель ещё не доставлен: стираем только слово и просим
    /// исполнителя дослать `sep` после перепечатки. В legacy-режиме
    /// разделитель уже напечатан — стираем и перепечатываем его вместе со
    /// словом (ADR 0004).
    private func boundaryReplace(
        original: String, with text: String, sep: Character, switchTo: Lang?) -> EngineOutcome {
        if separatorAlreadyTyped {
            return EngineOutcome(command: .replaceLast(
                len: original.count + 1, with: text + String(sep), switchTo: switchTo),
                                 expectedText: original + String(sep))
        }
        return EngineOutcome(
            command: .replaceLast(len: original.count, with: text, switchTo: switchTo),
            expectedText: original,
            reinjectSeparator: sep)
    }

    // MARK: - Конвертация/откат (хоткей .convert, прежний Option)

    private func handleConvert() -> EngineOutcome {
        // Откат недавнего авто-исправления: всегда возвращаем как было; в
        // исключения слово уходит только по достижении порога отмен (spec G03).
        if let auto = lastAuto, now() - auto.time <= undoWindow {
            if auto.separator.isEmpty {
                setBuffer(to: auto.original)
                liveApplied = false
                wordEdited = true
                manuallyCorrectedWord = true
            }
            lastAuto = nil
            lastRegion = Region(word: auto.original, separator: auto.separator)
            let command = EngineCommand.replaceLast(
                len: auto.corrected.count + auto.separator.count,
                with: auto.original + auto.separator,
                switchTo: auto.originalLang)

            let key = auto.original.lowercased()
            let bumped = (undoCounts[key] ?? 0) + 1
            if bumped >= undoThreshold {
                // Порог достигнут — исключаем слово и сбрасываем счётчик.
                detector.addExclusion(auto.original)
                undoCounts[key] = 0
                return EngineOutcome(
                    command: command,
                    expectedText: auto.corrected + auto.separator,
                    excludedWordToPersist: auto.original,
                    undoCountUpdate: (word: auto.original, count: 0))
            } else {
                // Ниже порога — только считаем, слово не исключаем.
                undoCounts[key] = bumped
                return EngineOutcome(
                    command: command,
                    expectedText: auto.corrected + auto.separator,
                    undoCountUpdate: (word: auto.original, count: bumped))
            }
        }

        // Ручная конвертация. Незавершённое слово в буфере имеет приоритет.
        if !buffer.word.isEmpty {
            let word = buffer.word
            let target = Self.conversionTarget(for: word)
            let converted = KeyMap.convert(word, to: target)
            setBuffer(to: converted)
            manuallyCorrectedWord = true
            lastRegion = nil
            return EngineOutcome(command: .replaceLast(
                len: word.count, with: converted, switchTo: target), expectedText: word)
        }

        // Иначе — последнее завершённое слово вместе с его разделителем.
        if let region = lastRegion, !region.word.isEmpty {
            let target = Self.conversionTarget(for: region.word)
            let converted = KeyMap.convert(region.word, to: target)
            lastRegion = Region(word: converted, separator: region.separator)
            return EngineOutcome(command: .replaceLast(
                len: region.word.count + region.separator.count,
                with: converted + region.separator,
                switchTo: target), expectedText: region.word + region.separator)
        }

        return .none
    }

    // MARK: - Вспомогательное

    private static let cyrillicSet =
        Set("абвгдежзийклмнопрстуфхцчшщъыьэюяёАБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯЁ")

    /// Куда конвертировать при ручном Option: слово с кириллицей → в EN,
    /// иначе → в RU. Так повторный Option естественно возвращает как было.
    private static func conversionTarget(for word: String) -> Lang {
        word.contains(where: { cyrillicSet.contains($0) }) ? .en : .ru
    }

    private func setBuffer(to text: String) {
        buffer.reset()
        for ch in text { buffer.append(char: ch) }
    }
}
