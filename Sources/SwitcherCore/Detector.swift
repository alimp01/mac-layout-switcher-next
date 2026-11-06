import Foundation

/// Decision for a completed token or a high-confidence live candidate.
public enum Verdict: Equatable, Sendable {
    case ru
    case en
    case unsure
}

/// Keyboop's dictionary/trigram cascade behind the existing per-session API.
/// Construct before installing input callbacks: initialization reads all four JSON files.
/// Calls and exclusions belong to the owning engine's serial context, as before.
public final class Detector {
    private let data: LayoutData
    private var exclusions: Set<String> = []
    private var previousWord: String?
    private var earlierWord: String?

    /// Explicit preparation status. Missing/corrupt resources disable all auto decisions.
    public var isReady: Bool { data.isLoaded }

    /// A directory override supports isolated CLI consumers/tests. App callers use the
    /// bundled shared immutable tables; this never reads an environment/global override.
    public init(dataDirectory: URL? = nil) {
        data = dataDirectory.map { LayoutData(directory: $0) } ?? LayoutData.shared
    }

    /// Добавляет слово в исключения (сравнение без учёта регистра).
    public func addExclusion(_ word: String) {
        exclusions.insert(word.lowercased())
    }

    func removeExclusion(_ word: String) { exclusions.remove(word.lowercased()) }

    /// Есть ли слово в исключениях (без учёта регистра).
    public func isExcluded(_ word: String) -> Bool {
        return exclusions.contains(word.lowercased())
    }

    /// Загружает исключения из файла (JSON-массив строк).
    /// Отсутствующий или битый файл означает пустой набор, а не ошибку.
    public func load(from url: URL) {
        guard
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode([String].self, from: data)
        else {
            exclusions = []
            return
        }
        exclusions = Set(decoded.map { $0.lowercased() })
    }

    /// Сохраняет исключения в файл (JSON-массив строк, отсортирован
    /// для стабильности диффов).
    public func save(to url: URL) {
        guard let data = try? JSONEncoder().encode(exclusionList) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Снимок исключений (нижний регистр, отсортирован — тот же формат, что
    /// пишет `save(to:)`). Для записи с фоновой очереди: снимок берётся
    /// синхронно, файл пишется без обращения к живому состоянию детектора.
    public var exclusionList: [String] { exclusions.sorted() }

    /// Forget both context words when the owning engine changes input context.
    public func resetContext() {
        previousWord = nil
        earlierWord = nil
    }

    public func verdict(for word: String, afterCaretJump: Bool = false) -> Verdict {
        guard isReady else { return .unsure }
        let decision: SwapDecision
        if isDecisionExcluded(word) || Self.isTechnicalToken(word) {
            decision = .keep
        } else if word.hasCyrillic && word.hasLatinLetter {
            // Upstream invokes this in Engine before decide(); putting it at this
            // public seam ensures every boundary caller receives mixed-word rescue.
            decision = LayoutDetector.mixedRescue(word: word, data: data)
        } else {
            decision = LayoutDetector.decide(word: word, exceptions: exceptionSnapshot,
                                             data: data, prev: previousWord, earlier: earlierWord,
                                             afterCaretJump: afterCaretJump)
        }
        let result = Self.verdict(decision)
        let displayed: String
        switch result {
        case .ru: displayed = convertedText(for: word, to: .ru)
        case .en: displayed = convertedText(for: word, to: .en)
        case .unsure: displayed = word
        }
        // Keep the legacy rule that unresolved mixed tokens do not change language
        // context. Numeric neighbours are retained for Keyboop's measurement guard.
        if displayed.hasCyrillic != displayed.hasLatinLetter || LayoutDetector.isNumericToken(displayed) {
            earlierWord = previousWord
            previousWord = displayed
        }
        return result
    }

    /// Does not advance phrase context or learn exclusions. UI/platform live gates
    /// (Chromium, secure input, focus ownership) remain the engine's responsibility.
    public func liveVerdict(for word: String) -> Verdict {
        guard isReady, !isDecisionExcluded(word), !Self.isTechnicalToken(word) else { return .unsure }
        return Self.verdict(LayoutDetector.liveDecide(word: word, exceptions: exceptionSnapshot, data: data))
    }

    /// Boundary conversion retains punctuation unless it is part of a known RU word.
    public func convertedText(for word: String, to language: Lang) -> String {
        guard isReady else { return word }
        if word.hasCyrillic && word.hasLatinLetter {
            return Keymap.convert(word, toCyrillic: language == .ru)
        }
        return Keymap.smartConvert(word, toCyrillic: language == .ru,
                                  isValidTarget: { self.data.wordsRu.contains($0) })
    }

    /// nil asks the live caller to wait: a final '.', ',' or ';' may be a letter in
    /// the unfinished target, and the boundary punctuation rule must not truncate it.
    public func liveConvertedText(for word: String, to language: Lang) -> String? {
        guard isReady else { return nil }
        return Keymap.liveConvert(word, toCyrillic: language == .ru,
                                 isValidTarget: { self.data.wordsRu.contains($0) })
    }

    private var exceptionSnapshot: LayoutExceptions { LayoutExceptions(ignored: exclusions) }

    private static func isTechnicalToken(_ word: String) -> Bool {
        // Preserve our identifier protection when upstream letterCore would strip
        // the terminal signs and mistake C++ / C# for the Russian preposition c.
        word.contains { "+#_=@\\/".contains($0) }
    }

    private func isDecisionExcluded(_ word: String) -> Bool {
        let whole = word.lowercased()
        let literal = LayoutDetector.letterCore(of: whole)
        let typed = Keymap.core(of: literal)
        var core = Substring(literal)
        while core.first?.isNumber == true { core = core.dropFirst() }
        while core.last?.isNumber == true { core = core.dropLast() }
        return exclusions.contains(whole) || exclusions.contains(literal)
            || exclusions.contains(typed) || exclusions.contains(String(core))
    }

    private static func verdict(_ decision: SwapDecision) -> Verdict {
        switch decision {
        case .keep: return .unsure
        case .convert(let toCyrillic): return toCyrillic ? .ru : .en
        }
    }
}
