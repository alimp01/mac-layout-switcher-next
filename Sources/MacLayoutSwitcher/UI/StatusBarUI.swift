// Слой UI/звуков macOS. Весь файл — под #if os(macOS): на Linux target
// собирается в пустой executable, чтобы `swift build`/`swift test` были зелёными.
#if os(macOS)
import AppKit
import SwitcherCore

/// Иконка в меню-баре и её меню (история R06i). NSStatusItem + NSMenu, без
/// SwiftUI-окон — минимальная поверхность. Владеет только отображением и
/// состоянием тумблеров; что делать по переключению — решают колбэки, которые
/// проставляет `main` (Engine / Config / Sounds). Persist настроек — за
/// колбэками (они пишут `Config`), UI лишь хранит и рисует текущее состояние.
///
/// В самом меню-баре — не картинка, а ТЕКУЩАЯ РАСКЛАДКА текстом («RU»/«EN»,
/// история G09): `setLayoutIndicator` дёргает `main` по системному уведомлению
/// смены источника ввода и после каждого programmatic select. Утка — иконка
/// приложения (AppIcon.icns), в трее её не рисуем.
public final class StatusBarUI: NSObject {

    /// Отображаемое состояние тумблеров.
    public struct State {
        /// Пауза (перехват выключен): иконка приглушается.
        public var paused: Bool
        /// Автопереключение по детектору.
        public var autoSwitch: Bool
        /// Звуки ввода.
        public var sounds: Bool
        /// Автозапуск при входе — по ФАКТУ (`LoginItem.isEnabled`), не по config.
        public var launchAtLogin: Bool

        public init(paused: Bool, autoSwitch: Bool, sounds: Bool, launchAtLogin: Bool = false) {
            self.paused = paused
            self.autoSwitch = autoSwitch
            self.sounds = sounds
            self.launchAtLogin = launchAtLogin
        }
    }

    // Pause requests a desired state; the owner confirms it after Engine.start.
    public var onTogglePause: ((Bool) -> Void)?
    // Other toggles report their new state.
    public var onToggleAutoSwitch: ((Bool) -> Void)?
    public var onToggleSounds: ((Bool) -> Void)?
    /// Тумблер автозапуска. Аргумент — ЖЕЛАЕМОЕ состояние. Колбэк сам пробует
    /// enable/disable и обязан вернуть галочку в факт через `setLaunchAtLoginState`
    /// (при ошибке — в прежнее положение). UI сам галочку НЕ переставляет.
    public var onToggleLaunchAtLogin: ((Bool) -> Void)?
    public var onOpenSnippets: (() -> Void)?
    public var onOpenConfig: (() -> Void)?
    public var onOpenHotkeys: (() -> Void)?
    /// «Проверить обновления…» — ручная проверка (main дёргает Updater).
    public var onCheckUpdates: (() -> Void)?
    public var onDictation: (() -> Void)?
    public var onQuit: (() -> Void)?

    private var state: State
    private var statusItem: NSStatusItem?

    // Индикатор раскладки: что показывать на кнопке статус-итема.
    // nil → «--» (источник не опознан как RU/EN: IME, другой язык).
    private var layoutLang: Lang?
    private var dictationStatus = ""
    // Приглушить индикатор (пауза перехвата): серый цвет + значок паузы.
    private var layoutPaused = false

    private var pauseItem: NSMenuItem?
    private var autoItem: NSMenuItem?
    private var soundsItem: NSMenuItem?
    private var launchItem: NSMenuItem?

    /// Версия из Info.plist (заполняет build.sh); вне бандла — «dev».
    private let version: String

    public init(state: State,
                version: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev") {
        self.state = state
        self.version = version
        super.init()
    }

    /// Создаёт иконку в меню-баре и вешает меню. Вызывать на главном потоке
    /// после старта NSApplication.
    public func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Вместо картинки на кнопке — текст текущей раскладки («RU»/«EN»);
        // до первого setLayoutIndicator показываем «--».
        item.button?.toolTip = "Mac Layout Switcher Next"
        item.menu = buildMenu()
        statusItem = item
        refresh()
    }

    /// Обновляет отображение под новое состояние (например, автопаузу извне).
    public func show(state: State) {
        self.state = state
        refresh()
    }

    /// Точечно синхронизирует галочку автопереключения, когда его поменяли
    /// снаружи меню (хоткей `.toggleAuto`). Паузу/звуки не трогает.
    public func setAutoSwitchState(_ on: Bool) {
        state.autoSwitch = on
        refresh()
    }

    public func setPausedState(_ paused: Bool) {
        state.paused = paused
        refresh()
    }

    /// Синхронизирует галочку автозапуска с ФАКТИЧЕСКИМ статусом
    /// (`LoginItem.isEnabled`). Вызывать при старте и после каждой попытки
    /// enable/disable — так галочка отражает истину, а не намерение, и ошибка
    /// register/unregister откатывает её в прежнее положение.
    public func setLaunchAtLoginState(_ on: Bool) {
        state.launchAtLogin = on
        refresh()
    }

    /// Индикатор текущей раскладки на кнопке статус-итема: «RU»/«EN», nil →
    /// «--». `paused` — приглушить (серый + «⏸»): перехват стоит на паузе.
    /// Обновление приходит от `main` по событию (системное уведомление смены
    /// источника ввода / после programmatic select) — поллинга нет.
    public func setLayoutIndicator(_ lang: Lang?, paused: Bool) {
        layoutLang = lang
        layoutPaused = paused
        refresh()
    }

    public func setDictationStatus(_ status: String) {
        dictationStatus = status
        renderLayoutIndicator()
    }

    // MARK: - Построение меню

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Mac Layout Switcher Next", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())

        let pause = NSMenuItem(
            title: "", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        pauseItem = pause
        menu.addItem(pause)

        menu.addItem(.separator())

        let auto = NSMenuItem(
            title: "Автопереключение", action: #selector(toggleAuto), keyEquivalent: "")
        auto.target = self
        autoItem = auto
        menu.addItem(auto)

        let sounds = NSMenuItem(
            title: "Звуки", action: #selector(toggleSounds), keyEquivalent: "")
        sounds.target = self
        soundsItem = sounds
        menu.addItem(sounds)

        let launch = NSMenuItem(
            title: "Запускать при входе", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launch.target = self
        launchItem = launch
        menu.addItem(launch)

        let dictation = NSMenuItem(title: "Диктовка…", action: #selector(openDictation), keyEquivalent: "")
        dictation.target = self
        menu.addItem(dictation)

        let hotkeys = NSMenuItem(
            title: "Горячие клавиши…", action: #selector(openHotkeys), keyEquivalent: "")
        hotkeys.target = self
        menu.addItem(hotkeys)

        menu.addItem(.separator())

        let openSnippets = NSMenuItem(
            title: "Открыть snippets.json", action: #selector(openSnippets), keyEquivalent: "")
        openSnippets.target = self
        menu.addItem(openSnippets)

        let openConfig = NSMenuItem(
            title: "Открыть config.json", action: #selector(openConfig), keyEquivalent: "")
        openConfig.target = self
        menu.addItem(openConfig)

        menu.addItem(.separator())

        let updates = NSMenuItem(
            title: "Проверить обновления…", action: #selector(checkUpdates), keyEquivalent: "")
        updates.target = self
        menu.addItem(updates)

        let about = NSMenuItem(
            title: "О программе", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(
            title: "Выход", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    /// Перерисовывает заголовки/галочки/индикатор под текущее состояние.
    private func refresh() {
        pauseItem?.title = state.paused ? "Работа (снять паузу)" : "Пауза"
        autoItem?.state = state.autoSwitch ? .on : .off
        soundsItem?.state = state.sounds ? .on : .off
        launchItem?.state = state.launchAtLogin ? .on : .off
        renderLayoutIndicator()
    }

    /// Рисует текст раскладки на кнопке статус-итема. Жирный моноширинный
    /// мелкий шрифт — «RU»/«EN» не прыгает по ширине; в паузе — серый
    /// (`secondaryLabelColor`, адаптируется к теме) с префиксом «⏸».
    private func renderLayoutIndicator() {
        guard let button = statusItem?.button else { return }
        let paused = layoutPaused || state.paused
        let lang = layoutLang.map { $0.rawValue.uppercased() } ?? "--"
        let text = (paused ? "⏸ " + lang : lang) + (dictationStatus.isEmpty ? "" : " " + dictationStatus)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .bold),
            .foregroundColor: paused ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ]
        button.attributedTitle = NSAttributedString(string: text, attributes: attributes)
    }

    // MARK: - Действия

    @objc private func togglePause() {
        onTogglePause?(!state.paused)
    }

    @objc private func toggleAuto() {
        state.autoSwitch.toggle()
        refresh()
        onToggleAutoSwitch?(state.autoSwitch)
    }

    @objc private func toggleSounds() {
        state.sounds.toggle()
        refresh()
        onToggleSounds?(state.sounds)
    }

    /// В отличие от прочих тумблеров галочку тут НЕ переставляем сразу: просим
    /// ЖЕЛАЕМОЕ состояние, а факт вернёт колбэк через `setLaunchAtLoginState`
    /// (при ошибке register/unregister галочка останется прежней — без ложного
    /// успеха).
    @objc private func toggleLaunchAtLogin() {
        onToggleLaunchAtLogin?(!state.launchAtLogin)
    }

    @objc private func openDictation() { onDictation?() }
    @objc private func openSnippets() { onOpenSnippets?() }
    @objc private func openConfig() { onOpenConfig?() }
    @objc private func openHotkeys() { onOpenHotkeys?() }
    @objc private func checkUpdates() { onCheckUpdates?() }
    @objc private func quit() { onQuit?() }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Mac Layout Switcher Next \(version)"
        alert.informativeText = """
        Свой аналог Punto Switcher и Caramba Switcher — бесплатный и открытый.

        Punto для Mac заброшен Яндексом с 2017 года и на новых macOS не работает; \
        Caramba жива, но закрыта и по подписке. Наш вариант: автоматика + \
        Option-хоткей + автозамена по шаблонам + звуки, без дневника, весь код у вас.
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
#endif
