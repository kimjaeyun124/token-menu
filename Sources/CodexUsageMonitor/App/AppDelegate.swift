import AppKit
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let refreshService: UsageRefreshService
    private var menuBarController: MenuBarController?
    private let logger = Logger(subsystem: "com.kimjaeyun.codexusagemonitor", category: "Lifecycle")

    override init() {
#if DEBUG
        if ProcessInfo.processInfo.environment["CODEX_USAGE_TEST_SCENARIO"] == "weekly-only" {
            let now = Date()
            refreshService = UsageRefreshService(provider: RuntimeFixtureUsageProvider(
                usage: CodexUsage(
                    fiveHourRemainingPercent: nil,
                    weeklyRemainingPercent: 84,
                    fiveHourResetDate: nil,
                    weeklyResetDate: now.addingTimeInterval(6 * 24 * 60 * 60),
                    lastUpdated: now,
                    source: "Runtime fixture"
                )
            ))
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
            visibility: visibility
        )
        self.menuBarController = menuBarController
        visibility.configure(menuBarController: menuBarController)
        visibility.applyStoredSettings()
        refreshService.start()
        let isLoginLaunch = ProcessInfo.processInfo.arguments.contains("--background-login")
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

#if DEBUG
private struct RuntimeFixtureUsageProvider: CodexUsageProviding {
    let usage: CodexUsage
    func fetchUsage() async throws -> CodexUsage { usage }
}
#endif
