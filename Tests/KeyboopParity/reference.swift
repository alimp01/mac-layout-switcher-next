import Foundation

// Only process/UI dependencies are stubbed. Language source files are compiled unchanged.
enum DynamicKeymap {
    static let isReady = false
    static let enToRu: [Character: Character] = [:]
    static let ruToEn: [Character: Character] = [:]
}
final class ExceptionStore {
    static let shared = ExceptionStore()
    var ignored: Set<String> = []
    var learned: Set<String> = []
    var forceSwap: Set<String> = []
}

struct Case: Codable {
    let word: String
    let prev: String?
    let earlier: String?
    let exclusions: [String]?
    var boundary: String?
    var live: String?
    var mixed: String?
    var converted: String?
    var liveConverted: String?
}
func label(_ decision: SwapDecision) -> String {
    switch decision {
    case .keep: return "unsure"
    case .convert(let toCyrillic): return toCyrillic ? "ru" : "en"
    }
}
@main struct Reference {
    static func main() throws {
        let input = URL(fileURLWithPath: CommandLine.arguments[1])
        var cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: input))
        guard LayoutData.shared.isLoaded else { fatalError("Pinned reference resources did not load") }
        for i in cases.indices {
            let c = cases[i]
            let exceptions = ExceptionStore.shared
            exceptions.ignored = Set(c.exclusions ?? [])
            let boundary = LayoutDetector.decide(word: c.word, exceptions: exceptions,
                                                  prev: c.prev, earlier: c.earlier)
            let mixed = LayoutDetector.mixedRescue(word: c.word)
            let live = LayoutDetector.liveDecide(word: c.word)
            cases[i].boundary = label(boundary)
            cases[i].mixed = label(mixed)
            cases[i].live = label(live)
            if case .convert(let ru) = boundary {
                cases[i].converted = Keymap.smartConvert(c.word, toCyrillic: ru,
                    isValidTarget: { LayoutData.shared.wordsRu.contains($0) })
            }
            if case .convert(let ru) = live {
                cases[i].liveConverted = Keymap.liveConvert(c.word, toCyrillic: ru,
                    isValidTarget: { LayoutData.shared.wordsRu.contains($0) })
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(cases).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    }
}
