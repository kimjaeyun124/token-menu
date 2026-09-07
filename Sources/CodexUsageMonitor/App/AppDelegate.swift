import AppKit
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let refreshService = UsageRefreshService()
    private let logger = Logger(subsystem: "com.kimjaeyun.codexusagemonitor", category: "Lifecycle")

    func applicationDidFinishLaunching(_ notification: Notification) {
        let visibility = AppVisibilityController.shared
        visibility.configure(refreshService: refreshService)
        visibility.applyStoredSettings()
        refreshService.start()

        let isBackgroundLoginLaunch = ProcessInfo.processInfo.arguments.contains("--background-login")
        let shouldStayHidden = isBackgroundLoginLaunch
            && !visibility.showInDock
            && UserDefaults.standard.bool(forKey: SettingsKey.keepRunningWhenWindowClosed)

        if !shouldStayHidden {
            visibility.reopenMainWindow()
        }
        logger.notice("Launch complete; background hidden: \(shouldStayHidden)")
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        logger.notice("Received launch-again event")
        AppVisibilityController.shared.reopenMainWindow()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        let shouldTerminate = !UserDefaults.standard.bool(forKey: SettingsKey.keepRunningWhenWindowClosed)
        logger.notice("Last window closed; terminating: \(shouldTerminate)")
        return shouldTerminate
    }
}
