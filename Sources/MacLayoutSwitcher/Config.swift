// Системный слой macOS. Весь файл — под #if os(macOS): на Linux target
// собирается в пустой executable, чтобы `swift build`/`swift test` были зелёными.
#if os(macOS)
import Foundation
import SwitcherCore

/// Типизированные настройки приложения (config.json).
/// snippets.json и exclusions.json — отдельные файлы, ими владеют
/// `SnippetStore`/`Detector`; `Config` лишь отдаёт их URL.
public struct AppConfig: Codable, Equatable {
    /// Глобальный тумблер автоисправления по детектору.
    public var autoSwitch: Bool
    /// Озвучка клавиш (реализация звука — таск UI/звуков).
    public var sounds: Bool
    /// Приложения-исключения (bundle id) — в них автоматика молчит.
    public var excludedApps: [String]

    /// Порог отмен одной и той же замены перед авто-исключением слова
    /// (spec G03). Дефолт 3; `1` — исключение с первого отката.
    public var undoThreshold: Int

    /// Хоткей конвертации/отката (таск 08). Дефолт — одиночный Option
    /// (обратная совместимость: у существующих пользователей не меняется).
    public var convertHotkey: Hotkey

    /// Хоткей вкл/выкл автопереключения (таск 08). Дефолт — не назначен (`nil`).
    public var toggleAutoHotkey: Hotkey?

    public var dictationHotkey: Hotkey = .defaultDictation

    /// Желаемое состояние автозапуска при входе (таск 09, G06). Дефолт false.
    /// Это лишь ЖЕЛАНИЕ пользователя; факт — `SMAppService.status` (`LoginItem`).
    public var launchAtLogin: Bool

    /// Дефолтные исключения — терминалы/IDE, как у Caramba (spec, A01).
    public static let defaultExcludedApps = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.microsoft.VSCode",
    ]

    /// Дефолт порога отмен (spec G03).
    public static let defaultUndoThreshold = 3

    public static let `default` = AppConfig(
        autoSwitch: true,
        sounds: false,
        excludedApps: defaultExcludedApps,
        undoThreshold: defaultUndoThreshold,
        convertHotkey: .defaultConvert,
        toggleAutoHotkey: nil,
        launchAtLogin: false
    )
}

extension AppConfig {
    /// Ручной декодер: отсутствие поля → дефолт (Codable с дефолтом).
    /// Так старый config.json без `undoThreshold` грузится без ошибки, а
    /// добавление новых полей не ломает существующие файлы.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppConfig.default
        self.autoSwitch = try c.decodeIfPresent(Bool.self, forKey: .autoSwitch) ?? d.autoSwitch
        self.sounds = try c.decodeIfPresent(Bool.self, forKey: .sounds) ?? d.sounds
        self.excludedApps = try c.decodeIfPresent([String].self, forKey: .excludedApps) ?? d.excludedApps
        self.undoThreshold = try c.decodeIfPresent(Int.self, forKey: .undoThreshold) ?? d.undoThreshold
        // Старый config.json без хоткей-полей → дефолты (Option / не назначен).
        self.convertHotkey = try c.decodeIfPresent(Hotkey.self, forKey: .convertHotkey) ?? d.convertHotkey
        self.toggleAutoHotkey = try c.decodeIfPresent(Hotkey.self, forKey: .toggleAutoHotkey) ?? d.toggleAutoHotkey
        self.dictationHotkey = try c.decodeIfPresent(Hotkey.self, forKey: .dictationHotkey) ?? d.dictationHotkey
        // Старый config.json без поля автозапуска → false (выключено).
        self.launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
    }
}

/// Хранилище настроек в `~/Library/Application Support/MacLayoutSwitcherNext/`.
/// Дефолты при отсутствии файла; битый config.json → бэкап `.broken` рядом
/// и дефолты. Пути/дефолты/миграции спрятаны за этим типом.
public final class Config {

    /// Текущие настройки (после `load()`; до него — дефолты).
    public private(set) var config: AppConfig = .default

    /// Каталог с файлами настроек.
    public let directory: URL

    private var configURL: URL { directory.appendingPathComponent("config.json") }
    /// URL файла шаблонов автозамены (грузит `SnippetStore`).
    public var snippetsURL: URL { directory.appendingPathComponent("snippets.json") }
    /// URL файла слов-исключений (грузит/пишет `Detector`).
    public var exclusionsURL: URL { directory.appendingPathComponent("exclusions.json") }
    /// URL файла счётчиков отмен per-word (spec G03). JSON-словарь слово→число.
    public var undoCountsURL: URL { directory.appendingPathComponent("undo-counts.json") }

    /// `directory == nil` → штатный Application Support; иначе (тесты/перенос)
    /// заданный каталог.
    public init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory()
    }

    private static func defaultDirectory() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("MacLayoutSwitcherNext", isDirectory: true)
    }

    /// Читает config.json. Нет файла → дефолты и запись. Битый → бэкап
    /// `config.json.broken` и дефолты.
    public func load() {
        flushPersist()
        ensureDirectory()
        guard let data = try? Data(contentsOf: configURL) else {
            config = .default
            save()
            return
        }
        guard let decoded = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            backupBroken(configURL)
            config = .default
            save()
            return
        }
        config = decoded
    }

    /// Фоновая очередь записи. Все `save*` кодируют снимок на вызывающем
    /// потоке (микросекунды) и пишут файл здесь: вызовы приходят из колбэка
    /// активного event tap'а, где дисковый I/O держал бы клавиатуру всей
    /// системы и грозил `tapDisabledByTimeout`. Очередь последовательная —
    /// записи одного файла не обгоняют друг друга.
    private let persistQueue = DispatchQueue(label: "MacLayoutSwitcherNext.Persist", qos: .utility)

    /// Пишет config.json (атомарно, стабильный порядок ключей для диффов).
    /// Запись асинхронная, на `persistQueue`.
    public func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return }
        persist(data, to: configURL)
    }

    /// Меняет настройки (в памяти — сразу) и сохраняет (асинхронно).
    public func update(_ mutate: (inout AppConfig) -> Void) {
        mutate(&config)
        save()
    }

    /// Пишет exclusions.json (JSON-массив слов; порядок — как передан,
    /// `Detector.exclusionList` отдаёт отсортированный). Асинхронно.
    public func saveExclusions(_ words: [String]) {
        guard let data = try? JSONEncoder().encode(words) else { return }
        persist(data, to: exclusionsURL)
    }

    /// Дожидается всех поставленных записей — перед чтением файлов с диска
    /// (`load`), чтобы перечитать не устаревшую копию. Только с главного
    /// потока вне колбэка tap'а.
    private func flushPersist() {
        persistQueue.sync {}
    }

    private func persist(_ data: Data, to url: URL) {
        persistQueue.async { [self] in
            ensureDirectory()
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Читает счётчики отмен (JSON-словарь слово→число). Отсутствующий или
    /// битый файл означает пустой словарь, а не ошибку (как у exclusions).
    public func loadUndoCounts() -> [String: Int] {
        flushPersist()
        guard
            let data = try? Data(contentsOf: undoCountsURL),
            let decoded = try? JSONDecoder().decode([String: Int].self, from: data)
        else { return [:] }
        return decoded
    }

    /// Пишет счётчики отмен (атомарно, стабильный порядок ключей для диффов).
    /// Запись асинхронная, на `persistQueue`.
    public func saveUndoCounts(_ counts: [String: Int]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(counts) else { return }
        persist(data, to: undoCountsURL)
    }

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
    }

    private func backupBroken(_ url: URL) {
        let broken = url.appendingPathExtension("broken")
        try? FileManager.default.removeItem(at: broken)
        try? FileManager.default.moveItem(at: url, to: broken)
    }
}
#endif
