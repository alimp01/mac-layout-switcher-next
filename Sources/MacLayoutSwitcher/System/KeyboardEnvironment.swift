#if os(macOS)
import AppKit

/// Sampled outside EventTap. Classification may inspect the app bundle, while
/// the callback only reads this prepared snapshot. The worker independently
/// rechecks secure input, modifiers and application immediately before posting.
final class KeyboardEnvironment {
    private(set) var pid: pid_t?
    private(set) var bundleID: String?
    private(set) var secure = true
    private(set) var chromium = true
    var onChange: (() -> Void)?
    private var timer: DispatchSourceTimer?

    func start() {
        refresh()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(50))
        timer.setEventHandler { [weak self] in self?.refresh() }
        self.timer = timer
        timer.resume()
    }
    func stop() { timer?.cancel(); timer = nil }
    private func refresh() {
        let nextPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let nextBundle = FrontApp.bundleID
        let nextSecure = SecureInput.isActive
        let appChanged = pid != nextPID || bundleID != nextBundle
        let changed = appChanged || secure != nextSecure
        if appChanged { chromium = Self.isChromium(pid: nextPID, bundleID: nextBundle) }
        pid = nextPID; bundleID = nextBundle; secure = nextSecure
        if changed { onChange?() }
    }
    private static func isChromium(pid: pid_t?, bundleID: String?) -> Bool {
        guard let pid, let bundleID else { return true }
        // Keyboop's known family, extended with the parent app's framework
        // classifier: arbitrary Electron bundle identifiers must also be gated.
        let known: Set<String> = ["com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary",
            "com.brave.Browser", "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders",
            "com.tinyspeck.slackmacgap", "notion.id", "md.obsidian", "com.figma.Desktop",
            "com.workflowy.desktop", "com.spotify.client", "com.hnc.Discord", "com.linear",
            "org.whispersystems.signal-desktop", "com.vivaldi.Vivaldi", "company.thebrowser.Browser",
            "com.operasoftware.Opera", "ru.yandex.desktop.yandex-browser", "com.yandex.desktop.yandex-browser"]
        if known.contains(bundleID) || bundleID.hasPrefix("com.microsoft.edgemac") || bundleID.hasPrefix("org.chromium") { return true }
        guard let bundle = NSRunningApplication(processIdentifier: pid)?.bundleURL else { return true }
        let frameworks = bundle.appendingPathComponent("Contents/Frameworks")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: frameworks.path)) ?? []
        let family: Set<String> = ["Electron Framework.framework", "Codex Framework.framework", "Chromium Framework.framework",
            "Google Chrome Framework.framework", "Brave Browser Framework.framework", "Microsoft Edge Framework.framework",
            "Yandex Framework.framework", "Bitrix24 Framework.framework"]
        return names.contains { family.contains($0) }
    }
}
#endif
