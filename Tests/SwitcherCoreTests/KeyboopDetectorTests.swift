import XCTest
import Foundation
import SwitcherCore

/// Expectations are literal examples from pinned Keyboop, not calculated from our dictionaries.
final class KeyboopDetectorTests: XCTestCase {
    private struct Reference: Decodable {
        let word: String
        let prev: String?
        let earlier: String?
        let exclusions: [String]?
        let boundary: String
        let live: String
        let mixed: String
        let converted: String?
        let liveConverted: String?
    }

    private func verdict(_ label: String) -> Verdict {
        label == "ru" ? .ru : label == "en" ? .en : .unsure
    }

    func testPinnedUpstreamDecisionsThroughThePublicAPI() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "keyboop-reference", withExtension: "json"))
        let cases = try JSONDecoder().decode([Reference].self, from: Data(contentsOf: url))
        XCTAssertEqual(cases.count, 257)
        for c in cases {
            let detector = Detector()
            XCTAssertTrue(detector.isReady)
            if let earlier = c.earlier { _ = detector.verdict(for: earlier) }
            if let prev = c.prev { _ = detector.verdict(for: prev) }
            for word in c.exclusions ?? [] { detector.addExclusion(word) }
            let note = "\(c.earlier ?? "∅") / \(c.prev ?? "∅") / \(c.word)"
            // Explicit, literal deviations: our established shifted ANSI map supports
            // '<'/'>' as Б/Ю; technical-token protection keeps C++ and C# intact.
            let shiftedPunctuation = ["K><K>", "(K><K>)?!"].contains(c.word)
            let protectedTechnical = ["C++", "C#"].contains(c.word)
            let liveExpected = shiftedPunctuation ? "ru" : protectedTechnical ? "unsure" : c.live
            XCTAssertEqual(detector.liveVerdict(for: c.word), verdict(liveExpected), note)
            let expected = shiftedPunctuation ? "ru" : protectedTechnical ? "unsure"
                : c.mixed != "unsure" && c.exclusions == nil ? c.mixed : c.boundary
            XCTAssertEqual(detector.verdict(for: c.word), verdict(expected), note)
            if let converted = c.converted, !protectedTechnical {
                XCTAssertEqual(detector.convertedText(for: c.word, to: c.boundary == "ru" ? .ru : .en), converted, note)
            }
            if c.live != "unsure" {
                XCTAssertEqual(detector.liveConvertedText(for: c.word, to: c.live == "ru" ? .ru : .en), c.liveConverted, note)
            }
        }
    }

    func testLiveDecisionDoesNotAdvancePhraseContextAndExceptionsArePerDetector() {
        let detector = Detector()
        XCTAssertEqual(detector.verdict(for: "plan"), .unsure)
        XCTAssertEqual(detector.liveVerdict(for: "ghbdtn"), .ru)
        XCTAssertEqual(detector.verdict(for: "b"), .unsure, "live must not replace plan's classifier context")
        detector.addExclusion("ghbdtn")
        XCTAssertEqual(detector.liveVerdict(for: "ghbd"), .unsure, "learned exclusion prefixes protect live typing")
        XCTAssertEqual(detector.liveVerdict(for: "GHBDTN"), .unsure)
        XCTAssertEqual(Detector().liveVerdict(for: "ghbdtn"), .ru)
        detector.addExclusion("привtn")
        XCTAssertEqual(detector.verdict(for: "привtn"), .unsure, "mixed rescue must respect undo learning")
    }

    func testBoundaryAndLiveConversionPreservePunctuationAtTheirOwnSeams() {
        let detector = Detector()
        for (typed, expected) in [("ghbdtn.", "привет."), ("[kt,", "хлеб"), ("yj;", "нож"),
                                  ("GHBDTN!", "ПРИВЕТ!"), ("(K><K>)?!", "(ЛЮБЛЮ)?!")] {
            XCTAssertEqual(detector.verdict(for: typed), .ru)
            XCTAssertEqual(detector.convertedText(for: typed, to: .ru), expected)
        }
        XCTAssertEqual(detector.liveVerdict(for: "gthtrk."), .ru)
        XCTAssertNil(detector.liveConvertedText(for: "gthtrk.", to: .ru))
        XCTAssertEqual(detector.liveConvertedText(for: "gthtrk.x", to: .ru), "переключ")
    }

    func testMissingAndCorruptResourcesDisableAutomaticDecisions() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        let missing = Detector(dataDirectory: path)
        XCTAssertFalse(missing.isReady)
        XCTAssertEqual(missing.verdict(for: "ghbdtn"), .unsure)
        XCTAssertEqual(missing.liveVerdict(for: "ghbdtn"), .unsure)
        XCTAssertNil(missing.liveConvertedText(for: "ghbdtn", to: .ru))
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        for name in ["words_ru", "words_en", "trigrams_ru", "trigrams_en"] {
            try Data("invalid json".utf8).write(to: path.appendingPathComponent(name + ".json"))
        }
        XCTAssertFalse(Detector(dataDirectory: path).isReady)
    }

    func testPreparationRequiresEveryTableAndDecisionsDoNotReadFiles() throws {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/SwitcherCore/Resources")
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        for missingName in ["words_ru", "words_en", "trigrams_ru", "trigrams_en"] {
            try FileManager.default.copyItem(at: source, to: path)
            try FileManager.default.removeItem(at: path.appendingPathComponent(missingName + ".json"))
            let missing = Detector(dataDirectory: path)
            XCTAssertFalse(missing.isReady, missingName)
            XCTAssertEqual(missing.verdict(for: "ghbdtn"), .unsure)
            try FileManager.default.removeItem(at: path)
        }
        try FileManager.default.copyItem(at: source, to: path)
        let prepared = Detector(dataDirectory: path)
        XCTAssertTrue(prepared.isReady)
        try FileManager.default.removeItem(at: path)
        XCTAssertEqual(prepared.verdict(for: "ghbdtn"), .ru)
        XCTAssertEqual(prepared.liveVerdict(for: "ghbdtn"), .ru)
        XCTAssertEqual(prepared.convertedText(for: "ghbdtn.", to: .ru), "привет.")
    }

    func testMixedWordRescueReachesThePublicBoundaryDecision() {
        for (typed, result, corrected) in [
            ("привtn", Verdict.ru, "привет"),
            ("приdет", .ru, "привет"),
            ("ghbdет", .ru, "привет"),
            ("heддщ", .en, "hello")
        ] {
            XCTAssertEqual(Detector().verdict(for: typed), result, typed)
            XCTAssertEqual(KeyMap.convert(typed, to: result == .ru ? .ru : .en), corrected)
        }
        for typed in ["API-ключ", "C++код", "helloмир", "ноутбукmac", "приvet", "helло"] {
            XCTAssertEqual(Detector().verdict(for: typed), .unsure, typed)
        }
    }
}
