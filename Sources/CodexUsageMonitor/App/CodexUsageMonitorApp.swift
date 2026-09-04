import AppKit
import SwiftUI

@main
struct CodexUsageMonitorApp: App {
    @StateObject private var refreshService: UsageRefreshService

    init() {
        let service = UsageRefreshService()
        _refreshService = StateObject(wrappedValue: service)
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            service.start()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(refreshService)
        } label: {
            Text(refreshService.menuBarText)
                .monospacedDigit()
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(refreshService)
        }
    }
}

