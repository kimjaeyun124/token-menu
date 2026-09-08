import AppKit
import Network
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settingsStore = SettingsStore.shared
    let refreshService: UsageRefreshService
    private var menuBarController: MenuBarController?
    private var wakeObserver: NSObjectProtocol?
    private let connectivityMonitor = ConnectivityMonitor()
    private let logger = Logger(subsystem: "com.kimjaeyun.codexusagemonitor", category: "Lifecycle")

    override init() {
#if DEBUG
        if ProcessInfo.processInfo.environment["CODEX_USAGE_TEST_SCENARIO"] == "weekly-only" {
            let now = Date()
            refreshService = UsageRefreshService(
                providers: [RuntimeFixtureUsageProvider(
                    usage: AIUsage(
                    provider: .codex,
                    windows: [UsageWindow(
                        type: .weekly,
                        remainingPercent: 84,
                        resetDate: now.addingTimeInterval(6 * 24 * 60 * 60)
                    )],
                    lastUpdated: now,
                    source: "Runtime fixture"
                )
                )],
                settingsStore: .shared
            )
        } else {
            refreshService = UsageRefreshService()
        }
#else
        refreshService = UsageRefreshService()
#endif
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let visibility = AppVisibilityController.shared
        let menuBarController = MenuBarController(
            refreshService: refreshService,
            settingsStore: settingsStore,
            visibility: visibility
        )
        self.menuBarController = menuBarController
        visibility.configure(menuBarController: menuBarController, refreshService: refreshService)
        visibility.applyStoredSettings()
        refreshService.start()
        let isLoginLaunch = ProcessInfo.processInfo.arguments.contains("--background-login")
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak refreshService] _ in
            Task { @MainActor in refreshService?.handleWake() }
        }
        connectivityMonitor.start { [weak refreshService] in
            Task { @MainActor in refreshService?.handleNetworkReconnect() }
        }
        let shouldOpen = isLoginLaunch
            ? !settingsStore.settings.startHiddenAtLogin
            : settingsStore.settings.openPopoverAfterLaunch
        let shouldOpenSettings = ProcessInfo.processInfo.arguments.contains("--show-settings")
        if shouldOpenSettings {
            DispatchQueue.main.async { visibility.showSettings() }
        } else if shouldOpen {
            DispatchQueue.main.async { visibility.showUsage() }
        }
        logger.notice("Menu bar launch complete; login launch: \(isLoginLaunch)")
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        logger.notice("Received launch-again event")
        AppVisibilityController.shared.showUsage()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        logger.notice("Window closed; menu bar app remains running")
        return false
    }
}

private final class ConnectivityMonitor {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.kimjaeyun.codexusagemonitor.network")
    private var hasSeenUnavailable = false

    func start(onReconnect: @escaping @Sendable () -> Void) {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            if path.status == .satisfied, hasSeenUnavailable {
                hasSeenUnavailable = false
                onReconnect()
            } else if path.status != .satisfied {
                hasSeenUnavailable = true
            }
        }
        monitor.start(queue: queue)
    }
}

#if DEBUG
private struct RuntimeFixtureUsageProvider: AIUsageProvider {
    let usage: AIUsage
    var id: AIProvider { usage.provider }
    var displayName: String { id.displayName }
    func isAvailable() async -> Bool { true }
    func fetchUsage() async throws -> AIUsage { usage }
}
#endif
