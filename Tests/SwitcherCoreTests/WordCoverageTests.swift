import XCTest
import Foundation
import SwitcherCore

/// Literal fixtures from G18's independent audit, never from production dictionaries.
final class WordCoverageTests: XCTestCase {
    // Next: ordinary EN neighbours no longer silence RU prepositions. Only the
    // pinned upstream's explicit label classifiers (plan/vitamin/model...) do.
    func testEveryRussianSingleLetterWordUsesTheSameContextRule() {
        let pairs = [("f", "а"), ("d", "в"), ("b", "и"), ("r", "к"),
                     ("j", "о"), ("c", "с"), ("e", "у"), ("z", "я")]
        for (input, output) in pairs {
            for (typed, expected) in [(input, output), (input.uppercased(), output.uppercased())] {
                for seed in ["", "привет", "hello"] {
                    let detector = Detector()
                    if !seed.isEmpty { _ = detector.verdict(for: seed) }
                    XCTAssertEqual(detector.verdict(for: typed), .ru,
                                   "\(seed) → \(typed)")
                    XCTAssertEqual(KeyMap.convert(typed, to: .ru), expected)
                    XCTAssertEqual(Detector().verdict(for: expected), .unsure)
                }
            }
        }
        for input in ["I", "i", "a", "A", ",", ";", ".", "'", "[", "]", "`", "~",
                      "q", "w", "t", "y", "u", "o", "p", "g", "h", "k", "l", "x", "v", "n", "m", "s"] {
            XCTAssertEqual(Detector().verdict(for: input), .unsure, input)
        }
    }
    private static let lexicalPairs: [(String, String)] = [
        ("yb", "ни"), (",ele", "буду"), ("vjue", "могу"), ("tldf", "едва"),
        ("dsit", "выше"), ("dfie", "вашу"), ("yfie", "нашу"), ("ytve", "нему"),
        ("dpzk", "взял"), ("ldev", "двум"), ("lde[", "двух"), ("tlf", "еда"),
        ("tlbv", "едим"), ("tlzn", "едят"), ("tcn", "ест"), ("pyfk", "знал"),
        ("hfl", "рад"), ("hfls", "рады"), ("ctk", "сел"), ("cgzn", "спят"),
        ("eue", "угу"), ("[v", "хм"), ("[p", "хз"), ("[kt,", "хлеб"),
        ("rjat", "кофе"), ("afqk", "файл"), ("rjulf", "когда"), ("njulf", "тогда"),
        ("byjulf", "иногда"), ("gecnm", "пусть"), ("gthtl", "перед"), ("chtlb", "среди"),
        ("kexit", "лучше"), ("vtymit", "меньше"), ("cegth", "супер"), ("rhenj", "круто"),
        ("dtxth", "вечер"), ("afqks", "файлы"), ("vjuen", "могут"), (",elen", "будут"),
        ("k.,k.", "люблю")
    ]

    func testAuditedLexicalGapsAndValidWordsAcrossCaseAndContext() {
        for (input, output) in Self.lexicalPairs {
            // Uppercase physical punctuation must be mapped from Russian:
            // ЛЮБЛЮ is K><K>, not K.,K. Lowercase expectations above are literal.
            let cases = [(input, output),
                         (KeyMap.convert(output.capitalized, to: .en), output.capitalized),
                         (KeyMap.convert(output.uppercased(), to: .en), output.uppercased())]
            for (typed, expected) in cases {
                for seed in ["", "привет", "hello"] {
                    let detector = Detector()
                    if !seed.isEmpty { _ = detector.verdict(for: seed) }
                    // Pinned Keyboop deliberately protects titlecase names mid-phrase,
                    // keeps yb (ytterbium) after EN, and has no хз dictionary entry.
                    let nameAfterWord = !seed.isEmpty && typed.first?.isUppercase == true
                        && typed.dropFirst().contains(where: { $0.isLowercase })
                    let upstreamKeep = nameAfterWord || (input == "yb" && seed == "hello") || output == "хз"
                    XCTAssertEqual(detector.verdict(for: typed), upstreamKeep ? .unsure : .ru, "\(seed) → \(typed)")
                    XCTAssertEqual(KeyMap.convert(typed, to: .ru), expected)
                    detector.resetContext()
                    if !seed.isEmpty { _ = detector.verdict(for: seed) }
                    XCTAssertEqual(detector.verdict(for: expected), .unsure, expected)
                }
            }
        }
        for word in ["bbc", "brb", "rfc", "xml", "ozon", "hello", "api", "json", "swift"] {
            for input in [word, word.capitalized, word.uppercased()] {
                for seed in ["", "привет", "hello"] {
                    let detector = Detector()
                    if !seed.isEmpty { _ = detector.verdict(for: seed) }
                    XCTAssertEqual(detector.verdict(for: input), .unsure, input)
                }
            }
        }
    }

    func testKeyboopCollisionsProtectValidSourcesAndOnlyForceDocumentedPairs() {
        // Literal pinned decisions supersede G18's symmetric collision set. Valid
        // words herb/tv/ev and all their Russian pairs stay in their source language.
        let cases: [(String, Verdict, Verdict, Verdict)] = [
            ("ns", .ru, .unsure, .ru), ("jq", .ru, .ru, .ru), ("ble", .ru, .ru, .ru),
            ("herb", .unsure, .unsure, .unsure), ("tv", .unsure, .unsure, .unsure),
            ("ev", .unsure, .unsure, .unsure), ("ты", .unsure, .unsure, .unsure),
            ("ой", .unsure, .unsure, .unsure), ("руки", .unsure, .unsure, .unsure),
            ("ем", .unsure, .unsure, .unsure), ("ум", .unsure, .unsure, .unsure),
            ("иду", .unsure, .unsure, .unsure)
        ]
        for (word, fresh, english, russian) in cases {
            for input in [word, word.uppercased()] {
                for (seed, expected) in [("", fresh), ("hello", english), ("привет", russian)] {
                    let detector = Detector()
                    if !seed.isEmpty { _ = detector.verdict(for: seed) }
                    XCTAssertEqual(detector.verdict(for: input), expected, "\(seed) → \(input)")
                    detector.resetContext()
                    XCTAssertEqual(detector.verdict(for: input), fresh)
                }
            }
        }
    }
    func testSafeWrappersPreservePhysicalLettersAndLanguageContext() {
        let pairs: [(String, String, Verdict)] = [
            ("ghbdtn!", "привет!", .ru), ("rfr?", "как?", .ru),
            ("(yt)", "(не)", .ru), ("(yt)!", "(не)!", .ru), ("((yt))", "((не))", .ru),
            ("руддщ!", "hello!", .en), ("ерфе?", "that?", .en),
            ("Rfr?", "Как?", .ru), ("GHBDTN!", "ПРИВЕТ!", .ru),
            ("b!", "и!", .ru), ("(z)", "(я)", .ru),
            ("cgfcb,j", "спасибо", .ru), ("k.,k.", "люблю", .ru), ("(K><K>)?!", "(ЛЮБЛЮ)?!", .ru)
        ]
        for (input, output, expected) in pairs {
            XCTAssertEqual(Detector().verdict(for: input), expected, input)
            XCTAssertEqual(KeyMap.convert(input, to: expected == .ru ? .ru : .en), output)
        }
        for seed in ["hello!", "(hello)", "((hello))?!"] {
            let detector = Detector()
            XCTAssertEqual(detector.verdict(for: seed), .unsure)
            XCTAssertEqual(detector.verdict(for: "B!"), .ru, "hello is not a label classifier")
        }
        let detector = Detector()
        XCTAssertEqual(detector.verdict(for: "(привет)!"), .unsure)
        XCTAssertEqual(detector.verdict(for: "(ns)?"), .ru)
    }

    func testIdentifiersAndValidPunctuatedWordsStayIntact() {
        for input in ["hello!", "ozon?", "(api)", "привет!", "файл!", "https://example.com",
                      "user@example.com", "example.com", "node.js", "hello_world", "snake_case",
                      "camelCase", "someVariable", "HTTPServer", "b2b", "a+b=c",
                      "foo(bar)",
                      "ghbdtn?key=value", "C++", "C#", "!?!", "()", "(())"] {
            for seed in ["", "привет", "hello"] {
                let detector = Detector()
                if !seed.isEmpty { _ = detector.verdict(for: seed) }
                XCTAssertEqual(detector.verdict(for: input), .unsure, "\(seed) → \(input)")
            }
        }
    }

    func testKeyboopNormalizesEdgesBeforeLanguageDetection() {
        // These were intentionally blocked by G18. Keyboop accepts surrounding
        // punctuation and long words with edge digits, including unbalanced wrappers.
        for input in ["ghbdtn123", "ghbdtn()", "!ghbdtn", "?ghbdtn", "(ghbdtn", "ghbdtn)"] {
            for seed in ["", "привет", "hello"] {
                let detector = Detector()
                if !seed.isEmpty { _ = detector.verdict(for: seed) }
                XCTAssertEqual(detector.verdict(for: input), .ru, input)
            }
        }
    }

    func testExclusionsProtectWholeTokenAndBareCoreAcrossCase() throws {
        let detector = Detector()
        detector.addExclusion("b")
        detector.addExclusion("GhBdTn")
        detector.addExclusion("(RFR)?")
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        detector.save(to: path)
        let loaded = Detector()
        loaded.load(from: path)
        for input in ["(B)!", "GHBDTN!", "((ghbdtn))?", "(rfr)?"] {
            XCTAssertEqual(loaded.verdict(for: input), .unsure, input)
        }
        XCTAssertEqual(Detector().verdict(for: "(B)!"), .ru)
    }
    private func type(_ input: String, into core: EngineCore) {
        for ch in input { XCTAssertEqual(core.handle(.char(ch)), .none) }
    }

    func testEnglishLabelsFollowPinnedClassifiersThroughTheEngine() {
        for (label, letter) in [("plan", "b"), ("drive", "c"), ("vitamin", "d"), ("option", "f"),
                                ("model", "r"), ("team", "e"), ("channel", "j"), ("model", "z")] {
            for input in [letter, letter.uppercased()] {
                let core = EngineCore(detector: Detector(), snippets: SnippetStore())
                type(label, into: core)
                XCTAssertEqual(core.handle(.boundary(" ")), .none)
                type(input, into: core)
                let boundary = core.handle(.boundary(" "))
                // drive/team/channel were protected by G18's blanket EN rule;
                // pinned Keyboop does not classify them as letter labels.
                if ["drive", "team", "channel"].contains(label) {
                    let text = label == "drive" ? "с" : label == "team" ? "у" : "о"
                    XCTAssertEqual(boundary.command, .replaceLast(len: 1,
                        with: input == letter ? text : text.uppercased(), switchTo: .ru))
                } else {
                    XCTAssertEqual(boundary, .none, "\(label) \(input)")
                }
            }
        }
    }

    func testWrappedCorrectionsKeepExactSourceAndSeparator() {
        for (input, output) in [("(Rfr)?!", "(Как)?!"), ("((yt))!", "((не))!"),
                                ("(K><K>)?!", "(ЛЮБЛЮ)?!"), ("D!", "В!")] {
            for separator: Character in [" ", "\n", "\t"] {
                for alreadyTyped in [false, true] {
                    let core = EngineCore(detector: Detector(), snippets: SnippetStore(),
                                          separatorAlreadyTyped: alreadyTyped)
                    type(input, into: core)
                    let outcome = core.handle(.boundary(separator))
                    let suffix = alreadyTyped ? String(separator) : ""
                    XCTAssertEqual(outcome.expectedText, input + suffix)
                    XCTAssertEqual(outcome.command, .replaceLast(len: input.count + suffix.count,
                                                                 with: output + suffix, switchTo: .ru))
                    XCTAssertEqual(outcome.reinjectSeparator, alreadyTyped ? nil : separator)
                    if separator != " " {
                        XCTAssertEqual(core.handle(.hotkey(.convert)), .none)
                    }
                }
            }
        }
    }

    func testNewlineAndTabClearKeyboopClassifierContext() {
        for separator: Character in ["\n", "\t"] {
            let core = EngineCore(detector: Detector(), snippets: SnippetStore())
            type("plan", into: core)
            XCTAssertEqual(core.handle(.boundary(separator)), .none)
            type("b", into: core)
            XCTAssertEqual(core.handle(.boundary(" ")).command,
                           .replaceLast(len: 1, with: "и", switchTo: .ru),
                           "after reset plan must no longer protect the letter b")
        }
    }

    func testWrappedUndoLearnsExactTokenAndCanBeDiscarded() {
        let detector = Detector()
        let core = EngineCore(detector: detector, snippets: SnippetStore(), undoThreshold: 1)
        type("(Rfr)!", into: core)
        XCTAssertEqual(core.handle(.boundary(" ")).command,
                       .replaceLast(len: 6, with: "(Как)!", switchTo: .ru))
        let undo = core.handle(.hotkey(.convert))
        XCTAssertEqual(undo.expectedText, "(Как)! ")
        XCTAssertEqual(undo.command, .replaceLast(len: 7, with: "(Rfr)! ", switchTo: .en))
        XCTAssertEqual(undo.excludedWordToPersist, "(Rfr)!")
        XCTAssertEqual(undo.undoCountUpdate?.word, "(Rfr)!")
        XCTAssertEqual(undo.undoCountUpdate?.count, 0)
        XCTAssertEqual(detector.verdict(for: "(RFR)!"), .unsure)
        XCTAssertEqual(detector.verdict(for: "rfr"), .ru, "wrapped undo stays token-scoped")
        core.discardReplacement(undo)
        XCTAssertEqual(detector.verdict(for: "(RFR)!"), .ru, "failed undo must not teach")
    }

    func testResetPauseAndDisabledAutocorrectionKeepNewTokensUntouched() {
        for mode in ["reset", "pause", "off"] {
            let core = EngineCore(detector: Detector(), snippets: SnippetStore())
            type("(ghbdtn)!", into: core)
            if mode == "reset" { _ = core.handle(.reset) }
            if mode == "pause" { core.isPaused = true }
            if mode == "off" { core.autoSwitch = false }
            XCTAssertEqual(core.handle(.boundary(" ")), .none)
            if mode == "pause" {
                type("D", into: core)
                core.isPaused = false
                XCTAssertEqual(core.handle(.hotkey(.convert)), .none)
            }
        }
        let detector = Detector()
        detector.addExclusion("d")
        let excluded = EngineCore(detector: detector, snippets: SnippetStore())
        type("(D)!", into: excluded)
        XCTAssertEqual(excluded.handle(.boundary(" ")), .none)
    }
}
