import ServiceManagement
import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var refreshService: UsageRefreshService
    @EnvironmentObject private var visibility: AppVisibilityController
    @AppStorage(SettingsKey.showInDock) private var showInDock = true
    @AppStorage(SettingsKey.dockBadgeSelection) private var dockBadgeSelection = DockBadgeSelection.fiveHour.rawValue
    @AppStorage(SettingsKey.keepRunningWhenWindowClosed) private var keepRunningWhenWindowClosed = true
    @AppStorage(SettingsKey.globalShortcutEnabled) private var globalShortcutEnabled = true
    @AppStorage(SettingsKey.refreshInterval) private var refreshInterval = RefreshInterval.fiveMinutes.rawValue
    @AppStorage(SettingsKey.notificationThreshold) private var notificationThreshold = NotificationThreshold.twenty.rawValue
    @State private var launchAtLogin = LoginItemService.isEnabled
    @State private var settingsError: String?

    var body: some View {
        Form {
            Section("Dock") {
                Toggle("Show in Dock", isOn: $showInDock)
                    .onChange(of: showInDock) { visible in
                        visibility.setDockVisibility(visible)
                    }

                Picker("Dock Badge", selection: $dockBadgeSelection) {
                    ForEach(DockBadgeSelection.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .disabled(!showInDock)
                .onChange(of: dockBadgeSelection) { _ in refreshService.settingsDidChange() }

                LabeledContent("Current Mode", value: visibility.activationPolicyStatus)
            }

            Section("Application") {
                Toggle("Keep Running When Window Is Closed", isOn: $keepRunningWhenWindowClosed)

                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in updateLaunchAtLogin(enabled) }
            }

            Section("Reopen Shortcut") {
                Toggle("Global Shortcut", isOn: $globalShortcutEnabled)
                    .onChange(of: globalShortcutEnabled) { enabled in
                        visibility.setGlobalShortcutEnabled(enabled)
                    }
                LabeledContent("Shortcut", value: visibility.shortcutStatus)
                Text("You can also reopen the window from the Dock, Spotlight, Applications, or by launching the app again.")
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

            LabeledContent("Detected Codex", value: refreshService.detectedCodexVersion)
            LabeledContent("Data Source", value: "Official app-server")

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
