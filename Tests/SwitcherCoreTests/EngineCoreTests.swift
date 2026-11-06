import XCTest
import Foundation
@testable import SwitcherCore

/// Тесты ядра склейки — единственный шов, проверяемый на Linux (spec).
/// Ожидаемые значения взяты из спецификации и разобраны вручную
/// («ghbdtn»→«привет»), а не вычислены тем же кодом, что под тестом.
final class EngineCoreTests: XCTestCase {

    /// Управляемые часы — окно отката проверяем без реального времени.
    private final class Clock {
        var t: Double = 1000
        func now() -> Double { t }
    }

    private func makeSnippetStore(_ json: String?) throws -> SnippetStore {
        let store = SnippetStore()
        guard let json else { return store }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("engine-snips-\(UUID().uuidString).json")
        try json.write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        store.load(from: url)
        return store
    }

    private func type(_ core: EngineCore, _ s: String) {
        for ch in s { _ = core.handle(.char(ch)) }
    }

    // MARK: - Автоисправление

    func testWrongLayoutWordIsCorrectedBeforeSeparatorIsDelivered() throws {
        // Активный tap (G12): Enter перехвачен ДО доставки — стираем только
        // слово (6 символов), печатаем «привет», раскладка в RU, а разделитель
        // исполнитель дошлёт сам ПОСЛЕ перепечатки.
        let core = EngineCore(detector: Detector(), snippets: SnippetStore())
        type(core, "ghbdtn")
        let out = core.handle(.boundary("\n"))
        XCTAssertEqual(out.command,
            .replaceLast(len: 6, with: "привет", switchTo: .ru))
        XCTAssertEqual(out.reinjectSeparator, "\n")
    }

    func testValidWordIsLeftUntouched() throws {
        let core = EngineCore(detector: Detector(), snippets: SnippetStore())
        type(core, "hello")
        let out = core.handle(.boundary(" "))
        XCTAssertEqual(out.command, .none)
        // Исправлять нечего — разделитель должен пройти как есть, без досылки.
        XCTAssertNil(out.reinjectSeparator)
    }

    func testLegacyModeKeepsAlreadyTypedSeparatorInReplacement() throws {
        // ADR 0004 (listen-only tap): разделитель уже напечатан — стирается
        // вместе со словом (7 символов) и перепечатывается; досылать нечего.
        let core = EngineCore(detector: Detector(), snippets: SnippetStore(),
                              separatorAlreadyTyped: true)
        type(core, "ghbdtn")
        let out = core.handle(.boundary(" "))
        XCTAssertEqual(out.command,
            .replaceLast(len: 7, with: "привет ", switchTo: .ru))
        XCTAssertNil(out.reinjectSeparator)
    }

    func testCorrectionOnlyAtWordBoundaryNotMidWord() throws {
        let core = EngineCore(detector: Detector(), snippets: SnippetStore())
        // Пока разделитель не пришёл — никаких команд.
        for ch in "ghbdtn" {
            XCTAssertEqual(core.handle(.char(ch)).command, .none)
        }
    }

    // MARK: - Откат по Option

    func testOptionUndoesAutoCorrectionWithinWindowAndExcludes() throws {
        let clock = Clock()
        let detector = Detector()
        // Порог 1 = прежнее поведение: один откат в окне сразу исключает.
        let core = EngineCore(detector: detector, snippets: SnippetStore(),
                              undoWindow: 5, undoThreshold: 1, now: clock.now)
        type(core, "ghbdtn")
        _ = core.handle(.boundary(" "))
        clock.t += 3 // в пределах 5 с
        let out = core.handle(.hotkey(.convert))
        XCTAssertEqual(out.command,
            .replaceLast(len: 7, with: "ghbdtn ", switchTo: .en))
        XCTAssertEqual(out.excludedWordToPersist, "ghbdtn")
        XCTAssertTrue(detector.isExcluded("ghbdtn"))
        // После отката слово больше не исправляется автоматически.
        type(core, "ghbdtn")
        XCTAssertEqual(core.handle(.boundary(" ")).command, .none)
    }

    func testOptionOutsideWindowDoesNotUndo() throws {
        let clock = Clock()
        let core = EngineCore(detector: Detector(), snippets: SnippetStore(),
                              undoWindow: 5, now: clock.now)
        type(core, "ghbdtn")
        _ = core.handle(.boundary(" "))
        clock.t += 6 // окно истекло
        let out = core.handle(.hotkey(.convert))
        XCTAssertNil(out.excludedWordToPersist)
    }

    func testUndoBelowThresholdDoesNotExcludeButStillCorrects() throws {
        let clock = Clock()
        let detector = Detector()
        let core = EngineCore(detector: detector, snippets: SnippetStore(),
                              undoWindow: 5, undoThreshold: 3, now: clock.now)

        // Первый откат: слово возвращается, но в исключения НЕ уходит.
        type(core, "ghbdtn")
        _ = core.handle(.boundary(" "))
        clock.t += 1
        let first = core.handle(.hotkey(.convert))
        XCTAssertEqual(first.command,
            .replaceLast(len: 7, with: "ghbdtn ", switchTo: .en))
        XCTAssertNil(first.excludedWordToPersist)
        XCTAssertFalse(detector.isExcluded("ghbdtn"))
        XCTAssertEqual(first.undoCountUpdate?.word, "ghbdtn")
        XCTAssertEqual(first.undoCountUpdate?.count, 1)

        // Слово всё ещё исправляется автоматически (не исключено). Разделитель
        // ещё не доставлен: стираем только слово, пробел дошлёт исполнитель.
        type(core, "ghbdtn")
        clock.t += 1
        let again = core.handle(.boundary(" "))
        XCTAssertEqual(again.command,
            .replaceLast(len: 6, with: "привет", switchTo: .ru))
        XCTAssertEqual(again.reinjectSeparator, " ")

        // Второй откат — по-прежнему не исключает.
        clock.t += 1
        let second = core.handle(.hotkey(.convert))
        XCTAssertNil(second.excludedWordToPersist)
        XCTAssertEqual(second.undoCountUpdate?.count, 2)
        XCTAssertFalse(detector.isExcluded("ghbdtn"))

        // Третий откат — достигнут порог: исключает и сбрасывает счётчик.
        type(core, "ghbdtn")
        clock.t += 1
        _ = core.handle(.boundary(" "))
        clock.t += 1
        let third = core.handle(.hotkey(.convert))
        XCTAssertEqual(third.excludedWordToPersist, "ghbdtn")
        XCTAssertTrue(detector.isExcluded("ghbdtn"))
        XCTAssertEqual(third.undoCountUpdate?.word, "ghbdtn")
        XCTAssertEqual(third.undoCountUpdate?.count, 0)
    }

    func testUndoThresholdOfOneReproducesImmediateExclusion() throws {
        let clock = Clock()
        let detector = Detector()
        let core = EngineCore(detector: detector, snippets: SnippetStore(),
                              undoWindow: 5, undoThreshold: 1, now: clock.now)
        type(core, "ghbdtn")
        _ = core.handle(.boundary(" "))
        clock.t += 1
        let out = core.handle(.hotkey(.convert))
        XCTAssertEqual(out.excludedWordToPersist, "ghbdtn")
        XCTAssertTrue(detector.isExcluded("ghbdtn"))
    }

    func testUndoCountsAreIndependentPerWordAndCaseInsensitive() throws {
        let clock = Clock()
        let detector = Detector()
        // Начальные счётчики приходят из персиста; ключ «GHBDTN» в верхнем
        // регистре должен нормализоваться и совпасть с набранным «ghbdtn».
        let core = EngineCore(detector: detector, snippets: SnippetStore(),
                              undoWindow: 5, undoThreshold: 3,
                              undoCounts: ["GHBDTN": 2], now: clock.now)

        // Другое слово «cgfcb,j» (спасибо) считается независимо — первый откат
        // его не исключает.
        type(core, "cgfcb,j")
        _ = core.handle(.boundary(" "))
        clock.t += 1
        let other = core.handle(.hotkey(.convert))
        XCTAssertNil(other.excludedWordToPersist)
        XCTAssertFalse(detector.isExcluded("cgfcb,j"))

        // «ghbdtn» стартует с 2 (из персиста, регистронезависимо) → первый же
        // откат достигает порога 3 и исключает.
        type(core, "ghbdtn")
        clock.t += 1
        _ = core.handle(.boundary(" "))
        clock.t += 1
        let out = core.handle(.hotkey(.convert))
        XCTAssertEqual(out.excludedWordToPersist, "ghbdtn")
        XCTAssertTrue(detector.isExcluded("ghbdtn"))
    }

    // MARK: - Ручная конвертация по Option

    func testOptionConvertsInProgressWordAndTogglesBack() throws {
        let core = EngineCore(detector: Detector(), snippets: SnippetStore())
        type(core, "ghbdtn")
        let first = core.handle(.hotkey(.convert))
        XCTAssertEqual(first.command,
            .replaceLast(len: 6, with: "привет", switchTo: .ru))
        // Повторный Option возвращает как было.
        let second = core.handle(.hotkey(.convert))
        XCTAssertEqual(second.command,
            .replaceLast(len: 6, with: "ghbdtn", switchTo: .en))
    }

    func testOptionConvertsLastCompletedWord() throws {
        // Валидное английское слово детектор не трогает, но Option конвертирует
        // его безусловно, вместе с сохранённым разделителем.
        let core = EngineCore(detector: Detector(), snippets: SnippetStore())
        type(core, "hello")
        XCTAssertEqual(core.handle(.boundary(" ")).command, .none)
        let out = core.handle(.hotkey(.convert))
        XCTAssertEqual(out.command,
            .replaceLast(len: 6, with: "руддщ ", switchTo: .ru))
    }

    // MARK: - Сниппеты

    func testSnippetExpansionTakesPriorityOverDetector() throws {
        let store = try makeSnippetStore(#"{"сдр": "С днём рождения!"}"#)
        let core = EngineCore(detector: Detector(), snippets: store)
        type(core, "сдр")
        let out = core.handle(.boundary(" "))
        // Та же схема, что у исправления: подавить разделитель, стереть только
        // сокращение (3 символа), развернуть, дослать пробел после.
        XCTAssertEqual(out.command,
            .replaceLast(len: 3, with: "С днём рождения!", switchTo: nil))
        XCTAssertEqual(out.reinjectSeparator, " ")
    }

    // MARK: - Автопауза / сброс / тумблер

    func testPausedStaysSilentAndDoesNotBuffer() throws {
        let core = EngineCore(detector: Detector(), snippets: SnippetStore())
        core.isPaused = true
        type(core, "ghbdtn")
        XCTAssertEqual(core.handle(.boundary(" ")).command, .none)
        // Сняли паузу — старое слово не должно всплыть (буфер был сброшен).
        core.isPaused = false
        XCTAssertEqual(core.handle(.hotkey(.convert)).command, .none)
    }

    func testResetPreventsCorrection() throws {
        // Cmd/Ctrl-комбинация и автоповтор транслируются Engine'ом в .reset.
        let core = EngineCore(detector: Detector(), snippets: SnippetStore())
        type(core, "ghbdtn")
        _ = core.handle(.reset)
        XCTAssertEqual(core.handle(.boundary(" ")).command, .none)
    }

    func testAutoSwitchOffSilencesDetectorButOptionStillWorks() throws {
        let core = EngineCore(detector: Detector(), snippets: SnippetStore(),
                              autoSwitch: false)
        type(core, "ghbdtn")
        XCTAssertEqual(core.handle(.boundary(" ")).command, .none)
        // Option по-прежнему конвертирует последнее слово.
        let out = core.handle(.hotkey(.convert))
        XCTAssertEqual(out.command,
            .replaceLast(len: 7, with: "привет ", switchTo: .ru))
    }
    func testLiveProposalUsesHighConfidenceAndDefersUnfinishedPunctuation() {
        let core = EngineCore(detector: Detector(), snippets: SnippetStore())
        type(core, "ghbdtn")
        XCTAssertEqual(core.liveCorrection().command, .replaceLast(len: 6, with: "привет", switchTo: .ru))
        XCTAssertEqual(core.liveCorrection().command, .none)
        _ = core.handle(.reset)
        type(core, "gthtrk.")
        XCTAssertEqual(core.liveCorrection().command, .none)
        _ = core.handle(.char("x"))
        XCTAssertEqual(core.liveCorrection().command, .replaceLast(len: 8, with: "переключ", switchTo: .ru))
    }

    func testUndoOfLiveWordProtectsItsNextBoundary() {
        let core = EngineCore(detector: Detector(), snippets: SnippetStore())
        type(core, "ghbdtn")
        _ = core.liveCorrection()
        XCTAssertEqual(core.handle(.hotkey(.convert)).command, .replaceLast(len: 6, with: "ghbdtn", switchTo: .en))
        XCTAssertEqual(core.liveCorrection().command, .none)
        XCTAssertEqual(core.handle(.boundary(" ")).command, .none)
        XCTAssertEqual(core.handle(.hotkey(.convert)).expectedText, "ghbdtn ")
    }

    func testTrackedOverflowStaysInvalidUntilBoundaryAndReset() {
        let core = EngineCore(detector: Detector(), snippets: SnippetStore())
        type(core, String(repeating: "g", count: 65))
        _ = core.handle(.backspace)
        type(core, "ghbdtn")
        XCTAssertEqual(core.liveCorrection().command, .none)
        XCTAssertEqual(core.handle(.hotkey(.convert)).command, .none)
        XCTAssertEqual(core.handle(.boundary(" ")).command, .none)
        type(core, "ghbdtn")
        XCTAssertEqual(core.handle(.boundary(" ")).command, .replaceLast(len: 6, with: "привет", switchTo: .ru))
    }

    func testCaretJumpProtectsEditedFragmentOnlyUntilFirstBoundary() {
        let core = EngineCore(detector: Detector(), snippets: SnippetStore())
        _ = core.handle(.caretJump)
        _ = core.handle(.backspace)
        type(core, "г")
        XCTAssertEqual(core.handle(.boundary(" ")).command, .none)
        _ = core.handle(.caretJump)
        _ = core.handle(.boundary(" "))
        _ = core.handle(.backspace)
        type(core, "г")
        XCTAssertEqual(core.handle(.boundary(" ")).command, .replaceLast(len: 1, with: "u", switchTo: .en))
        _ = core.handle(.caretJump)
        _ = core.handle(.backspace)
        type(core, "г")
        XCTAssertEqual(core.handle(.hotkey(.convert)).command, .replaceLast(len: 1, with: "u", switchTo: .en))
        _ = core.handle(.reset)
        type(core, "г")
        XCTAssertEqual(core.handle(.boundary(" ")).command, .replaceLast(len: 1, with: "u", switchTo: .en))
    }

    func testManualChoiceSurvivesLiveContinuationUntilBoundary() {
        let core = EngineCore(detector: Detector(), snippets: SnippetStore())
        type(core, "hello")
        _ = core.handle(.hotkey(.convert))
        type(core, "ц")
        XCTAssertEqual(core.liveCorrection().command, .none)
        XCTAssertEqual(core.handle(.boundary(" ")).command, .none)
        type(core, "ghbdtn")
        XCTAssertEqual(core.liveCorrection().command, .replaceLast(len: 6, with: "привет", switchTo: .ru))
    }

    func testLivePreservesSnippetAndItsCaseSensitivePrefix() throws {
        for trigger in ["ghbdtn", "ghbdtnX"] {
            let store = try makeSnippetStore("{\"\(trigger)\":\"My custom snippet\"}")
            XCTAssertTrue(store.hasTrigger(startingWith: "ghbdtn"))
            XCTAssertFalse(store.hasTrigger(startingWith: "GHBDTN"))
            let core = EngineCore(detector: Detector(), snippets: store)
            type(core, "ghbdtn")
            XCTAssertEqual(core.liveCorrection().command, .none)
            if trigger == "ghbdtnX" { type(core, "X") }
            XCTAssertEqual(core.handle(.boundary(" ")).command,
                           .replaceLast(len: trigger.count, with: "My custom snippet", switchTo: nil))
        }
    }

    func testTechnicalFocusResetPreservesCaretEditGuard() {
        for editBeforeRefresh in [false, true] {
            let core = EngineCore(detector: Detector(), snippets: SnippetStore())
            _ = core.handle(.caretJump)
            if editBeforeRefresh { _ = core.handle(.backspace) }
            core.resetTrackingPreservingCaretJump()
            if !editBeforeRefresh { _ = core.handle(.backspace) }
            type(core, "г")
            XCTAssertEqual(core.handle(.boundary(" ")).command, .none)
        }
    }

}
