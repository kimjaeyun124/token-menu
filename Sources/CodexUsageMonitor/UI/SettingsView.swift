import ServiceManagement
import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var refreshService: UsageRefreshService
    @EnvironmentObject private var visibility: AppVisibilityController
    @AppStorage(SettingsKey.menuBarSelection) private var menuBarSelection = MenuBarSelection.automatic.rawValue
    @AppStorage(SettingsKey.globalShortcutEnabled) private var globalShortcutEnabled = true
    @AppStorage(SettingsKey.refreshInterval) private var refreshInterval = RefreshInterval.fiveMinutes.rawValue
    @AppStorage(SettingsKey.notificationThreshold) private var notificationThreshold = NotificationThreshold.twenty.rawValue
    @State private var launchAtLogin = LoginItemService.isEnabled
    @State private var settingsError: String?

    var body: some View {
        Form {
            Section("Menu Bar") {
                Picker("Displayed Percentage", selection: $menuBarSelection) {
                    ForEach(MenuBarSelection.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .onChange(of: menuBarSelection) { _ in refreshService.settingsDidChange() }
                LabeledContent("App Mode", value: visibility.activationPolicyStatus)
            }

            Section("Application") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in updateLaunchAtLogin(enabled) }
                Text("Codex Usage stays available in the menu bar until you choose Quit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Reopen Shortcut") {
                Toggle("Global Shortcut", isOn: $globalShortcutEnabled)
                    .onChange(of: globalShortcutEnabled) { enabled in
                        visibility.setGlobalShortcutEnabled(enabled)
                    }
                LabeledContent("Shortcut", value: visibility.shortcutStatus)
                Text("The menu bar item is always the primary way to open Codex Usage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Usage") {
                Picker("Refresh Interval", selection: $refreshInterval) {
                    ForEach(RefreshInterval.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .onChange(of: refreshInterval) { _ in
                    refreshService.settingsDidChange(rescheduleTimer: true)
                }

                Picker("Low Usage Notification", selection: $notificationThreshold) {
                    ForEach(NotificationThreshold.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .onChange(of: notificationThreshold) { newValue in
                    if newValue != NotificationThreshold.off.rawValue {
                        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
                    }
                }
            }

            Section("Diagnostics") {
                LabeledContent("Detected Codex", value: refreshService.detectedCodexVersion)
                LabeledContent("Data Source", value: "Codex app-server account/rateLimits/read")
            }

            if let settingsError {
                Text(settingsError)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 520, height: 600)
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try LoginItemService.service.register()
            } else {
                try LoginItemService.service.unregister()
            }
            let status = LoginItemService.service.status
            launchAtLogin = status == .enabled || status == .requiresApproval
            settingsError = status == .requiresApproval
                ? "Approve Codex Usage under System Settings › General › Login Items."
                : nil
        } catch {
            launchAtLogin = LoginItemService.isEnabled
            settingsError = "Launch at Login requires the packaged application in Applications."
        }
    }
}

private enum LoginItemService {
    static let identifier = "com.kimjaeyun.codexusagemonitor.Launcher"
    static var service: SMAppService { SMAppService.loginItem(identifier: identifier) }
    static var isEnabled: Bool {
        let status = service.status
        return status == .enabled || status == .requiresApproval
    }
}
