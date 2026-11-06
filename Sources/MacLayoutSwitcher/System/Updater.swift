// Автообновление через GitHub (таск 13). Весь файл — под #if os(macOS):
// на Linux target собирается в пустой executable.
#if os(macOS)
import AppKit
import Foundation
import SwitcherCore

/// Проверка обновлений и запуск самообновления. Репозиторий публичный,
/// поэтому «последняя версия» — это просто raw-файл `VERSION` из ветки main;
/// релизов/тегов не требуется. Сравнение — `SemVer.compare` (SwitcherCore,
/// покрыто тестами на Linux).
///
/// Расписание: первая проверка через ~1 минуту после старта (не мешаем
/// онбордингу и подъёму Engine), дальше раз в 24 часа. Плюс ручная проверка
/// из меню («Проверить обновления…»). Фоновая проверка молчит всегда, кроме
/// найденного обновления (сбой сети — только NSLog); ручная отвечает всегда:
/// «версия актуальна», «не удалось проверить» или «запущено не из .app».
final class Updater {

    /// Raw VERSION из main — источник истины о последней версии.
    private static let versionURL = URL(
        string: "https://raw.githubusercontent.com/alimp01/mac-layout-switcher-next/main/VERSION")!

    /// Своя версия — из Info.plist (заполняет build.sh из файла VERSION).
    /// nil = запущено НЕ из собранного бандла (swift run, голый бинарник):
    /// в этом режиме обновление ОТКЛЮЧЕНО — self-update заменяет путь бандла,
    /// и вне .app он указывал бы на произвольный каталог (~/bin, .build/release).
    private let bundleVersion: String?

    /// Для алертов: версия бандла либо честное «не из .app».
    var currentVersion: String { bundleVersion ?? "0.0.0" }

    private var dailyTimer: Timer?
    private var initialTimer: Timer?
    /// Защита от наложения проверок (ручная поверх фоновой).
    private var checkInProgress = false

    init(currentVersion: String? =
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) {
        self.bundleVersion = Bundle.main.bundleIdentifier == "space.alimp.maclayoutswitcher.next"
            && Bundle.main.bundlePath.hasSuffix(".app") ? currentVersion : nil
    }

    /// Запускает расписание проверок. Вызывать один раз после старта UI.
    /// Timer с суточным интервалом — это не поллинг состояния, а редкая
    /// плановая проверка; tolerance отдаёт системе свободу экономить питание.
    func start() {
        let initial = Timer(timeInterval: 60, repeats: false) { [weak self] _ in
            self?.check(interactive: false)
        }
        initial.tolerance = 30
        RunLoop.main.add(initial, forMode: .common)
        initialTimer = initial

        let daily = Timer(timeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            self?.check(interactive: false)
        }
        daily.tolerance = 60 * 60
        RunLoop.main.add(daily, forMode: .common)
        dailyTimer = daily
    }

    /// Проверка «сейчас». `interactive` — запущено пунктом меню: тогда
    /// «версия актуальна» показывается алертом, а не молчанием.
    func check(interactive: Bool) {
        // Вне бандла обновление недоступно (см. bundleVersion): фоново —
        // молча в лог, вручную — честный алерт вместо ложного «доступна версия».
        guard let ownVersion = bundleVersion else {
            NSLog("MacLayoutSwitcherNext: запущено не из .app — проверка обновлений отключена")
            if interactive { presentNotFromBundleAlert() }
            return
        }
        guard !checkInProgress else { return }
        checkInProgress = true
        fetchLatest { [weak self] latest in
            guard let self = self else { return }
            self.checkInProgress = false
            guard let latest = latest else {
                // Фоновый сбой сети — молча (уже залогирован); ручной клик
                // обязан получить ответ, иначе пункт меню выглядит сломанным.
                if interactive { self.presentCheckFailedAlert() }
                return
            }
            if SemVer.compare(latest, ownVersion) == .orderedDescending {
                self.presentUpdateAlert(latest: latest.trimmingCharacters(in: .whitespacesAndNewlines))
            } else if interactive {
                self.presentUpToDateAlert()
            }
        }
    }

    // MARK: - Сеть

    /// GET raw VERSION. Завершение — на главной очереди; nil = сбой (сеть,
    /// не-2xx, кривое тело) — молча, детали в NSLog.
    private func fetchLatest(completion: @escaping (String?) -> Void) {
        var request = URLRequest(url: Updater.versionURL)
        request.timeoutInterval = 10
        // Кэш здесь вреден: raw.githubusercontent и так отдаёт мелкий файл,
        // а устаревший ответ отложит обновление на сутки.
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            var latest: String?
            if let error = error {
                NSLog("MacLayoutSwitcherNext: проверка обновлений не удалась: \(error.localizedDescription)")
            } else if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                NSLog("MacLayoutSwitcherNext: проверка обновлений: HTTP \(http.statusCode)")
            } else if let data = data,
                      let body = String(data: data, encoding: .utf8),
                      !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                latest = body
            } else {
                NSLog("MacLayoutSwitcherNext: проверка обновлений: пустой или нечитаемый VERSION")
            }
            DispatchQueue.main.async { completion(latest) }
        }
        task.resume()
    }

    // MARK: - Алерты

    private func presentUpdateAlert(latest: String) {
        let alert = NSAlert()
        alert.messageText = "Next: доступна версия \(latest)"
        alert.informativeText = """
        У тебя \(currentVersion). Обновить?

        Приложение скачает исходники, пересоберётся и перезапустится — это \
        займёт ~1–2 минуты (лог: ~/Library/Logs/MacLayoutSwitcherNext-update.log).

        Внимание: после обновления macOS попросит заново выдать разрешения \
        (Универсальный доступ и Мониторинг ввода) — замена приложения \
        сбрасывает выданное доверие.
        """
        alert.addButton(withTitle: "Обновить")
        alert.addButton(withTitle: "Позже")
        // «Позже» не делает ничего: следующий раз спросим при плановой
        // проверке (раз в сутки) или по пункту меню.
        if alert.runModal() == .alertFirstButtonReturn {
            runSelfUpdate()
        }
    }

    private func presentUpToDateAlert() {
        let alert = NSAlert()
        alert.messageText = "Next: версия актуальна"
        alert.informativeText = "У тебя последняя версия — \(currentVersion)."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func presentCheckFailedAlert() {
        let alert = NSAlert()
        alert.messageText = "Не удалось проверить обновления"
        alert.informativeText = """
        Не получилось узнать последнюю версию с GitHub (нет сети?). \
        Попробуйте позже — плановая проверка тоже повторится через сутки.
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func presentNotFromBundleAlert() {
        let alert = NSAlert()
        alert.messageText = "Обновление недоступно"
        alert.informativeText = """
        Приложение запущено не из собранного Next .app-бандла (например, напрямую \
        из терминала), поэтому самообновление отключено. Соберите и запустите \
        .app через ./build.sh.
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - Запуск самообновления

    /// Копирует self-update.sh из Resources бандла во временную папку и
    /// запускает КОПИЮ detached (nohup): скрипт заменит сам бандл, поэтому
    /// исполняемый файл не должен исчезнуть из-под bash. После запуска
    /// приложение выходит — скрипт соберёт новую версию и откроет её сам.
    private func runSelfUpdate() {
        // Скрипт заменяет только установленный .app (он валидирует путь тоже).
        let appPath = Bundle.main.bundlePath
        guard appPath.hasSuffix(".app"),
              Bundle.main.bundleIdentifier == "space.alimp.maclayoutswitcher.next" else {
            NSLog("MacLayoutSwitcherNext: bundlePath '\(appPath)' — не .app, самообновление отменено")
            return
        }
        guard let scriptURL = Bundle.main.url(forResource: "self-update", withExtension: "sh") else {
            NSLog("MacLayoutSwitcherNext: self-update.sh не найден в Resources бандла — обновление невозможно")
            presentUpdateStartFailedAlert()
            return
        }
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory
            .appendingPathComponent("MacLayoutSwitcherNext-update-\(ProcessInfo.processInfo.globallyUniqueString)")
        let tmpScript = tmpDir.appendingPathComponent("self-update.sh")
        do {
            try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            try fm.copyItem(at: scriptURL, to: tmpScript)
        } catch {
            NSLog("MacLayoutSwitcherNext: не удалось подготовить копию self-update.sh: \(error)")
            try? fm.removeItem(at: tmpDir)
            presentUpdateStartFailedAlert()
            return
        }

        // nohup: скрипт переживает выход приложения (setsid в macOS нет).
        // Вывода у него не остаётся — скрипт сам пишет всё в свой лог-файл.
        // Прямой Process не требует shell quoting и сообщает ошибку запуска.
        // PID позволяет дождаться завершения dictation.shutdown до замены
        // и открытия бандла; open не должен вернуть ещё старый процесс.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
        process.arguments = ["/bin/bash", tmpScript.path, appPath, tmpDir.path,
                             String(ProcessInfo.processInfo.processIdentifier)]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            NSLog("MacLayoutSwitcherNext: не удалось запустить self-update.sh: \(error)")
            try? fm.removeItem(at: tmpDir)
            presentUpdateStartFailedAlert()
            return
        }
        NSLog("MacLayoutSwitcherNext: самообновление запущено, выходим")
        NSApp.terminate(nil)
    }

    private func presentUpdateStartFailedAlert() {
        let alert = NSAlert()
        alert.messageText = "Не удалось запустить обновление"
        alert.informativeText = "Приложение продолжает работать. Проверьте свободное место и повторите «Проверить обновления…»."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
#endif
