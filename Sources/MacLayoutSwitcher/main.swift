// Точка входа приложения. Весь macOS-слой (EventTap, Typist, LayoutSwitcher,
// Engine, StatusBarUI, Sounds, Config) закрыт #if os(macOS): на Linux target
// собирается в пустой executable, чтобы `swift build`/`swift test` были зелёными.
#if os(macOS)
import AppKit
import Foundation

/// Делегат приложения: проверяет разрешения, поднимает Engine + меню-бар, либо
/// показывает онбординг разрешений (история R06i.1). Приложение — `.accessory`
/// (LSUIElement): без иконки в Dock, живёт только в меню-баре.
final class AppDelegate: NSObject, NSApplicationDelegate {

    // Config создаётся здесь и передаётся в Engine — общий экземпляр, чтобы
    // тумблеры меню и Engine писали/читали один и тот же файл настроек.
    private let config = Config()
    private lazy var captureSession = CaptureSessionGuard(directory: config.directory)

    private var engine: Engine?
    private var sounds: Sounds?
    private var ui: StatusBarUI?
    private var hotkeyWindow: HotkeyRecorderWindow?
    // Автозапуск при входе (SMAppService). Источник истины — сам сервис, не config.
    private let loginItem = LoginItem()
    // Проверка обновлений (raw VERSION с GitHub): отложенно при старте,
    // раз в сутки и по пункту меню.
    private let updater = Updater()

    // Отдельный статус-элемент онбординга (когда нет доверия и Engine не поднят).
    private var onboardingItem: NSStatusItem?

    // Индикатор раскладки в меню-баре (история G09): обновляется по событиям,
    // без поллинга. Токен наблюдателя системного уведомления держим, чтобы
    // подписка жила вместе с делегатом (живёт до выхода приложения);
    // manualPaused — пауза из меню (у Engine ручной паузы нет, факт живёт здесь).
    private var layoutObserver: NSObjectProtocol?
    private var manualPaused = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        do { try captureSession.acquire() }
        catch { refuseCapture(error); return }
        captureSession.onConflict = { [weak self] reason in self?.refuseCapture(reason) }
        captureSession.watchForConflicts()
        config.load()
        if Permissions.trusted {
            startSwitcher()
        } else {
            presentOnboarding()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let engine else { return .terminateNow }
        engine.stop()
        engine.dictation.shutdown { sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine?.stop()
    }

    // MARK: - Рабочий режим

    private func startSwitcher() {
        do { try captureSession.checkBeforeCapture() }
        catch { refuseCapture(error); return }
        let sounds = Sounds(enabled: config.config.sounds)
        let engine = Engine(config: config)
        engine.sounds = sounds
        // Стартуем перехват. Разрешение уже проверено, но система могла
        // отказать по иной причине — тогда падаем в онбординг.
        guard engine.start() else {
            presentOnboarding()
            return
        }

        // Факт автозапуска — из SMAppService, а не из config: пользователь мог
        // снять объект входа в Системных настройках. Расхождение config↔факт
        // разрешаем в пользу факта и приводим config к нему.
        let launchFact = loginItem.isEnabled
        if config.config.launchAtLogin != launchFact {
            config.update { $0.launchAtLogin = launchFact }
        }

        let ui = StatusBarUI(state: StatusBarUI.State(
            paused: false,
            autoSwitch: config.config.autoSwitch,
            sounds: config.config.sounds,
            launchAtLogin: launchFact))

        // Пауза = полностью снять/поднять перехват (у Engine нет ручной паузы;
        // автопауза secure-input/исключений считается внутри на каждое событие).
        // Индикатор раскладки при этом приглушается/оживает.
        ui.onTogglePause = { [weak self, weak engine] paused in
            guard let self, let engine else { return }
            if paused {
                engine.stop()
                self.manualPaused = true
            } else {
                do { try self.captureSession.checkBeforeCapture() }
                catch { self.refuseCapture(error); return }
                self.manualPaused = !engine.start()
            }
            self.ui?.setPausedState(self.manualPaused)
            self.updateLayoutIndicator()
            if !paused && self.manualPaused { self.showOnboardingAlert(resuming: true) }
        }
        ui.onToggleAutoSwitch = { [weak engine] on in
            engine?.setAutoSwitch(on)   // сам пишет config
        }
        ui.onToggleSounds = { [weak self] on in
            self?.sounds?.enabled = on
            self?.config.update { $0.sounds = on }
        }
        // Тумблер автозапуска: пробуем enable/disable, затем ВСЕГДА приводим
        // config и галочку к фактическому статусу. Ошибку register/unregister не
        // глотаем — логируем, config не меняем, галочка откатывается в факт
        // (в прежнее положение), без ложного успеха.
        ui.onToggleLaunchAtLogin = { [weak self] desired in
            guard let self = self else { return }
            do {
                if desired { try self.loginItem.enable() } else { try self.loginItem.disable() }
            } catch {
                NSLog("MacLayoutSwitcherNext: смена автозапуска не удалась: \(error)")
            }
            // На современных macOS register() часто не бросает ошибку, а ставит
            // статус .requiresApproval: объект входа создан, но ждёт подтверждения
            // в Системных настройках. isEnabled тут false — без подсказки
            // пользователь решит, что тумблер не сработал.
            if desired && !self.loginItem.isEnabled && self.loginItem.requiresApproval {
                self.presentLaunchApprovalNeeded()
            }
            let fact = self.loginItem.isEnabled
            self.config.update { $0.launchAtLogin = fact }
            self.ui?.setLaunchAtLoginState(fact)
        }
        ui.onOpenSnippets = { [weak self] in self?.openInEditor(self?.config.snippetsURL) }
        // config.json приватен внутри Config, но каталог публичен — собираем путь.
        ui.onOpenConfig = { [weak self] in
            self?.openInEditor(self?.config.directory.appendingPathComponent("config.json"))
        }
        ui.onOpenHotkeys = { [weak self] in self?.showHotkeys() }
        ui.onCheckUpdates = { [weak self] in self?.updater.check(interactive: true) }
        ui.onDictation = { [weak engine] in engine?.dictation.showSetup() }
        engine.dictation.onStatus = { [weak ui] status in ui?.setDictationStatus(status) }
        ui.onQuit = { NSApp.terminate(nil) }
        ui.install()

        // Расписание проверок обновлений: первая — через ~1 мин (не мешаем
        // старту), дальше раз в 24 ч. Фоновая проверка молчит, пока нет новой
        // версии; ручная (пункт меню) отвечает и «версия актуальна».
        updater.start()

        // Хоткей `.toggleAuto` меняет автопереключение мимо меню — синхронизируем
        // галочку.
        engine.onAutoSwitchChanged = { [weak ui] on in
            ui?.setAutoSwitchState(on)
        }

        self.sounds = sounds
        self.engine = engine
        self.ui = ui

        // Индикатор раскладки (история G09) — строго по событиям, без поллинга:
        // 1) системное уведомление смены источника ввода (пользователь сменил
        //    раскладку сам — ⌃Space, меню ввода, другое приложение);
        // 2) колбэк Engine после programmatic select (авто-исправление, Option) —
        //    не ждём системный бродкаст, обновляемся сразу;
        // 3) начальная установка при старте.
        // Имя уведомления — kTISNotifySelectedKeyboardInputSourceChanged
        // (HIToolbox), приходит через DistributedNotificationCenter.
        layoutObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(
                "com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"),
            object: nil,
            queue: .main) { [weak self] _ in
            self?.updateLayoutIndicator()
        }
        engine.onLayoutSwitched = { [weak self] _ in
            DispatchQueue.main.async { self?.updateLayoutIndicator() }
        }
        updateLayoutIndicator()
    }

    /// Stop our own capture before showing a conflict; never terminate another app.
    private func refuseCapture(_ error: Error) {
        engine?.stop()
        manualPaused = true
        ui?.setPausedState(true)
        let alert = NSAlert()
        alert.messageText = "Mac Layout Switcher Next: запуск остановлен"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "Закрыть Next")
        alert.runModal()
        NSApp.terminate(nil)
    }

    /// Перечитывает текущую раскладку и отдаёт её индикатору в меню-баре.
    /// Всегда спрашиваем систему (`LayoutSwitcher.current()`), а не кэш —
    /// уведомление лишь сигнал «что-то поменялось».
    private func updateLayoutIndicator() {
        ui?.setLayoutIndicator(LayoutSwitcher.current(), paused: manualPaused)
    }

    /// Открывает окно настройки горячих клавиш (создаётся лениво, переживает
    /// закрытие — один и тот же экземпляр).
    private func showHotkeys() {
        if hotkeyWindow == nil {
            hotkeyWindow = HotkeyRecorderWindow(config: config)
            hotkeyWindow?.onRecordingChanged = { [weak self] recording in
                self?.engine?.isRecordingHotkey = recording
            }
        }
        hotkeyWindow?.show()
    }

    /// Автозапуск зарегистрирован, но macOS ждёт подтверждения пользователем
    /// (статус `.requiresApproval`). Объясняем это и открываем панель «Объекты
    /// входа», чтобы включение не выглядело «ничего не произошло».
    private func presentLaunchApprovalNeeded() {
        let alert = NSAlert()
        alert.messageText = "Разрешите автозапуск"
        alert.informativeText = """
        macOS просит подтвердить автозапуск вручную. Откройте «Системные \
        настройки → Основные → Объекты входа» и включите «Mac Layout Switcher Next» \
        в списке — после этого приложение будет стартовать при входе.
        """
        alert.addButton(withTitle: "Открыть «Объекты входа»")
        alert.addButton(withTitle: "Позже")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            loginItem.openLoginItemsSettings()
        }
    }

    /// Открывает JSON-файл настроек во внешнем редакторе. Если файла ещё нет
    /// (пользователь не создавал шаблоны) — создаёт заготовку, иначе Finder
    /// откроет пустоту.
    private func openInEditor(_ url: URL?) {
        guard let url = url else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            let stub = url.lastPathComponent == "snippets.json" ? "{\n  \"сдр\": \"С днём рождения!\"\n}\n" : "{}\n"
            try? stub.data(using: .utf8)?.write(to: url, options: .atomic)
        }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Онбординг разрешений

    private func presentOnboarding() {
        // Пункт меню-бара, чтобы приложение было видимым и не выглядело
        // «тихим отказом»: из него можно повторно открыть настройки и выйти.
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "keyboard.badge.ellipsis",
                accessibilityDescription: "Mac Layout Switcher Next — нужны разрешения")
            button.image?.isTemplate = true
        }
        let menu = NSMenu()
        let access = NSMenuItem(title: "Открыть «Универсальный доступ»…",
                                action: #selector(openAccessibility), keyEquivalent: "")
        access.target = self
        menu.addItem(access)
        let input = NSMenuItem(title: "Открыть «Мониторинг ввода»…",
                               action: #selector(openInputMonitoring), keyEquivalent: "")
        input.target = self
        menu.addItem(input)
        menu.addItem(.separator())
        let recheck = NSMenuItem(title: "Я выдал разрешения — перезапустить",
                                 action: #selector(relaunch), keyEquivalent: "")
        recheck.target = self
        menu.addItem(recheck)
        let quit = NSMenuItem(title: "Выход", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        onboardingItem = item

        showOnboardingAlert()
    }

    private func showOnboardingAlert(resuming: Bool = false) {
        let alert = NSAlert()
        alert.messageText = resuming ? "Не удалось возобновить работу" : "Нужны разрешения"
        let resumeExplanation = resuming
            ? "Перехват клавиатуры не запустился. Приложение осталось на паузе. Проверьте разрешения ниже и повторите «Работа (снять паузу)»; если это не поможет, перезапустите приложение.\n\n"
            : ""
        let retryInstruction = resuming
            ? "После этого повторите «Работа (снять паузу)»."
            : "Затем перезапустите приложение (пункт меню-бара «Я выдал разрешения»)."
        alert.informativeText = resumeExplanation + """
        Mac Layout Switcher Next слушает клавиатуру во всех приложениях, поэтому \
        macOS требует два разрешения:

        1. Универсальный доступ (Accessibility) — чтобы перехватывать и \
        перепечатывать текст.
        2. Мониторинг ввода (Input Monitoring) — чтобы видеть нажатия клавиш.

        Откройте обе панели кнопками ниже и включите «Mac Layout Switcher Next». \
        \(retryInstruction)
        """
        alert.addButton(withTitle: "Открыть «Универсальный доступ»")
        alert.addButton(withTitle: "Открыть «Мониторинг ввода»")
        alert.addButton(withTitle: "Позже")
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            Permissions.openAccessibilitySettings()
        case .alertSecondButtonReturn:
            Permissions.openInputMonitoringSettings()
        default:
            break
        }
    }

    @objc private func openAccessibility() { Permissions.openAccessibilitySettings() }
    @objc private func openInputMonitoring() { Permissions.openInputMonitoringSettings() }
    @objc private func quitApp() { NSApp.terminate(nil) }

    /// Перезапуск после выдачи разрешений: TCC-доверие подхватывается новым
    /// процессом надёжнее, чем повторной проверкой в текущем.
    @objc private func relaunch() {
        let path = Bundle.main.bundlePath
        let process = Process()
        // Wait for this process (and its lifetime lock) to exit, including
        // dictation cleanup. Starting `open -n` first would correctly be refused.
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
        process.arguments = ["/bin/sh", "-c", """
            attempt=0
            while kill -0 "$2" 2>/dev/null; do
                [ "$attempt" -lt 30 ] || exit 1
                attempt=$((attempt + 1))
                sleep 1
            done
            exec /usr/bin/open "$1"
            """, "next-relaunch", path, String(ProcessInfo.processInfo.processIdentifier)]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run(); NSApp.terminate(nil) }
        catch {
            let alert = NSAlert()
            alert.messageText = "Не удалось перезапустить Next"
            alert.informativeText = "Завершите Next через меню и откройте приложение снова."
            alert.runModal()
        }
    }
}

let app = NSApplication.shared
// .accessory: без иконки в Dock и без пунктов главного меню — только меню-бар.
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
#endif
