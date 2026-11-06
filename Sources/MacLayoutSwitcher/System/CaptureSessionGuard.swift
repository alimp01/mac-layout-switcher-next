#if os(macOS)
import AppKit
import Darwin

/// Next owns this lock for its entire lifetime (including pause/onboarding).
/// Stable does not share it: its public workspace launch notifications stop Next
/// as early as macOS reports the conflict. This is not an atomic cross-app lock.
final class CaptureSessionGuard {
    struct Application {
        let pid: pid_t
        let bundleID: String?
        let executableName: String?

        init(pid: pid_t, bundleID: String?, executableName: String?) {
            self.pid = pid
            self.bundleID = bundleID
            self.executableName = executableName
        }

        init(_ app: NSRunningApplication) {
            self.init(pid: app.processIdentifier, bundleID: app.bundleIdentifier,
                      executableName: app.executableURL?.lastPathComponent)
        }
    }

    enum Refusal: LocalizedError {
        case stableRunning, nextRunning, lockUnavailable

        var errorDescription: String? {
            switch self {
            case .stableRunning:
                return "Уже запущен Mac Layout Switcher. Next остановлен, чтобы два приложения не исправляли один ввод. Завершите стабильную версию через её меню, затем откройте Next."
            case .nextRunning:
                return "Mac Layout Switcher Next уже запущен. Используйте его значок в строке меню."
            case .lockUnavailable:
                return "Не удалось проверить, запущен ли другой Next. Перехват клавиатуры не включён. Проверьте доступ к папке настроек Next и повторите запуск."
            }
        }
    }

    private let directory: URL
    private let applications: () -> [Application]
    private let ownPID: pid_t
    private let notifications: NotificationCenter
    private var descriptor: Int32 = -1
    private var observers: [NSObjectProtocol] = []
    private var conflictReported = false
    var onConflict: ((Refusal) -> Void)?

    init(directory: URL,
         applications: @escaping () -> [Application] = {
             NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }.map(Application.init)
         }, ownPID: pid_t = ProcessInfo.processInfo.processIdentifier,
         notifications: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        self.directory = directory
        self.applications = applications
        self.ownPID = ownPID
        self.notifications = notifications
    }

    deinit {
        observers.forEach(notifications.removeObserver)
        if descriptor >= 0 { close(descriptor) }
        // Keep the file: unlinking a locked inode permits a second owner.
    }

    func acquire() throws {
        guard !hasStableConflict() else { throw Refusal.stableRunning }
        if descriptor >= 0 { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch { throw Refusal.lockUnavailable }
        let path = directory.appendingPathComponent("capture.lock").path
        let candidate = Darwin.open(path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard candidate >= 0 else { throw Refusal.lockUnavailable }
        guard flock(candidate, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(candidate)
            throw code == EWOULDBLOCK ? Refusal.nextRunning : Refusal.lockUnavailable
        }
        descriptor = candidate
        guard !hasStableConflict() else { throw Refusal.stableRunning }
    }

    /// Recheck before every start/resume; never enable a tap after a conflict.
    func checkBeforeCapture() throws {
        guard descriptor >= 0, !conflictReported else { throw Refusal.lockUnavailable }
        guard !hasStableConflict() else { throw Refusal.stableRunning }
    }

    func watchForConflicts() {
        guard observers.isEmpty else { return }
        for name in [NSWorkspace.willLaunchApplicationNotification, NSWorkspace.didLaunchApplicationNotification] {
            observers.append(notifications.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self, !self.conflictReported else { return }
                let launched = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
                    .map(Application.init)
                if launched.map(self.isStableConflict) == true || self.hasStableConflict() {
                    self.conflictReported = true
                    self.onConflict?(.stableRunning)
                }
            })
        }
    }

    private func hasStableConflict() -> Bool { applications().contains(where: isStableConflict) }

    private func isStableConflict(_ app: Application) -> Bool {
        guard app.pid != ownPID, app.bundleID != "space.alimp.maclayoutswitcher.next" else { return false }
        return app.bundleID == "space.alimp.maclayoutswitcher"
            || app.executableName == "MacLayoutSwitcher"
    }
}
#endif
