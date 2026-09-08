import SwiftUI

@main
struct CodexUsageMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.refreshService)
                .environmentObject(appDelegate.settingsStore)
                .environmentObject(AppVisibilityController.shared)
        }
    }
}
