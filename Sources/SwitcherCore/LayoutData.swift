// Adapted from Keyboop fb9bdde4eb8f13a486974cf102a8bec9d607e5d2 (MIT).
// Language data: keyswitcher, Copyright (c) 2026 Ilya Granin. See THIRD_PARTY.md.
import Foundation

/// Immutable language tables, decoded once during Detector preparation.
final class LayoutData {
    static let shared = LayoutData(directory: packagedDirectory())

    let trigramsRu: [String: Double]
    let trigramsEn: [String: Double]
    let wordsRu: Set<String>
    let wordsEn: Set<String>
    let isLoaded: Bool

    init(directory: URL?) {
        let ruTrigrams: [String: Double] = Self.load("trigrams_ru", from: directory) ?? [:]
        let enTrigrams: [String: Double] = Self.load("trigrams_en", from: directory) ?? [:]
        let ruWords: [String] = Self.load("words_ru", from: directory) ?? []
        let enWords: [String] = Self.load("words_en", from: directory) ?? []
        trigramsRu = ruTrigrams
        trigramsEn = enTrigrams
        wordsRu = Set(ruWords).union(ExtraWords.ru).union(ExtraWords.ruDev)
            .union(ExtraWords.ruAbbr).union(ExtraWords.ruShort)
            .union(ExtraWords.ruCommonForms).union(ExtraWords.ruLoanNames)
        wordsEn = Set(enWords).union(ExtraWords.en)
        // Check all ORIGINAL resources: ExtraWords must not mask a missing word table.
        isLoaded = !ruTrigrams.isEmpty && !enTrigrams.isEmpty && !ruWords.isEmpty && !enWords.isEmpty
    }

    /// Upstream's padded mean trigram log-probability, with -20 for absent trigrams.
    func plausibility(_ word: String, cyrillic: Bool) -> Double {
        let table = cyrillic ? trigramsRu : trigramsEn
        let chars = Array(" " + word.lowercased() + " ")
        guard chars.count >= 3 else { return -.infinity }
        var sum = 0.0
        for i in 0...(chars.count - 3) {
            sum += table[String(chars[i..<(i + 3)])] ?? -20.0
        }
        return sum / Double(chars.count - 2)
    }

    private static func load<T: Decodable>(_ name: String, from directory: URL?) -> T? {
        guard let url = directory?.appendingPathComponent(name + ".json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// SwiftPM puts resources beside a CLI/test executable; the app packager puts
    /// the .bundle inside Contents/Resources. Explicit lookup avoids Bundle.module's
    /// fatalError when an installed bundle is missing. No I/O happens in verdicts.
    private static func packagedDirectory() -> URL? {
        let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent()
        let roots = [Bundle.main.resourceURL, Bundle.main.bundleURL, executableDirectory].compactMap { $0 }
        for root in roots {
            for suffix in ["bundle", "resources"] {
                let url = root.appendingPathComponent("MacLayoutSwitcher_SwitcherCore." + suffix)
                if let bundle = Bundle(url: url), let resources = bundle.resourceURL,
                   FileManager.default.fileExists(atPath: resources.appendingPathComponent("words_ru.json").path) {
                    return resources
                }
                if FileManager.default.fileExists(atPath: url.appendingPathComponent("words_ru.json").path) {
                    return url
                }
            }
        }
        return nil
    }
}

/// The port has no shared mutable ExceptionStore. Both explicit and undo-learned
/// keep words use Detector's existing exclusion set; force-swap UI is not imported.
struct LayoutExceptions {
    var ignored: Set<String>
    let learned: Set<String> = []
    let forceSwap: Set<String> = []
}
