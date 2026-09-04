import ServiceManagement
import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var refreshService: UsageRefreshService
    @AppStorage(SettingsKey.menuBarSelection) private var menuBarSelection = UsageSelection.fiveHour.rawValue
    @AppStorage(SettingsKey.dockBadgeSelection) private var dockBadgeSelection = DockBadgeSelection.fiveHour.rawValue
    @AppStorage(SettingsKey.refreshInterval) private var refreshInterval = RefreshInterval.fiveMinutes.rawValue
    @AppStorage(SettingsKey.notificationThreshold) private var notificationThreshold = NotificationThreshold.twenty.rawValue
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var settingsError: String?

    var body: some View {
        Form {
            Picker("Menu Bar Display", selection: $menuBarSelection) {
                ForEach(UsageSelection.allCases) { option in
                    Text(option.title).tag(option.rawValue)
                }
            }
            .onChange(of: menuBarSelection) { _ in refreshService.settingsDidChange() }

            Picker("Dock Badge", selection: $dockBadgeSelection) {
                ForEach(DockBadgeSelection.allCases) { option in
                    Text(option.title).tag(option.rawValue)
                }
            }
            .onChange(of: dockBadgeSelection) { _ in refreshService.settingsDidChange() }

            Picker("Refresh Interval", selection: $refreshInterval) {
                ForEach(RefreshInterval.allCases) { option in
                    Text(option.title).tag(option.rawValue)
                }
            }
            .onChange(of: refreshInterval) { _ in refreshService.settingsDidChange(rescheduleTimer: true) }

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

            Toggle("Launch at Login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { enabled in updateLaunchAtLogin(enabled) }

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
        .frame(width: 470, height: 360)
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            settingsError = nil
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            settingsError = "Launch at Login is available when running the packaged application."
        }
    }
}

