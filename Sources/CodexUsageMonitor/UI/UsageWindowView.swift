import AppKit
import SwiftUI

struct UsageWindowView: View {
    @EnvironmentObject private var refreshService: UsageRefreshService
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var visibility: AppVisibilityController
    @EnvironmentObject private var activityMonitor: CodexActivityMonitor

    var body: some View {
        let providers = refreshService.visibleProviders()
        let settings = settingsStore.settings

        VStack(alignment: .leading, spacing: settings.popoverSize == .compact ? 9 : 13) {
            Text(settingsStore.localized("app.title"))
                .font(.system(size: 16, weight: .semibold))

            if !activityMonitor.snapshot.activities.isEmpty {
                CodexActivityListView(activities: activityMonitor.snapshot.activities)
                Divider()
            }

            if providers.isEmpty {
                Text(settingsStore.localized("status.no_providers"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(providers.enumerated()), id: \.element) { index, provider in
                    if index > 0, settings.providerSeparators { Divider() }
                    providerSection(provider, settings: settings)
                }
            }

            if settings.showLastUpdatedTime, let latestUpdate {
                Divider()
                HStack(spacing: 6) {
                    Text(updatedText(latestUpdate))
                    if providers.contains(where: { refreshService.isStale($0) }) {
                        Text(settingsStore.localized("status.stale"))
                            .fontWeight(.semibold)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }

            if settings.showRefreshButton || settings.showSettingsButton || settings.showQuitButton {
                Divider()
                HStack(spacing: 8) {
                    if settings.showRefreshButton {
                        Button(settingsStore.localized("action.refresh")) {
                            Task { await refreshService.refresh(reason: .manual) }
                        }
                        .disabled(refreshService.isRefreshing)
                        .keyboardShortcut("r")
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    if settings.showSettingsButton {
                        Button(settingsStore.localized("action.settings")) { visibility.showSettings() }
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    if settings.showQuitButton {
                        Button(settingsStore.localized("action.quit")) { quit() }
                            .keyboardShortcut("q")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .buttonStyle(.borderless)
                .font(.system(size: 12))
            }
        }
        .padding(settings.popoverSize == .compact ? 13 : 18)
        .frame(width: settings.popoverWidth.points)
        .environment(\.locale, settings.language.locale)
        .onAppear { refreshService.popoverOpened() }
    }

    @ViewBuilder
    private func providerSection(_ provider: AIProvider, settings: AppSettings) -> some View {
        let preferences = settings.preferences(for: provider)
        let windows = refreshService.visibleWindows(for: provider)
        let stale = refreshService.isStale(provider)
        let mayShowData = !stale || settings.showStaleData

        VStack(alignment: .leading, spacing: settings.popoverSize == .compact ? 7 : 10) {
            HStack(spacing: 6) {
                if settings.showProviderIcons {
                    providerIcon(provider, color: settings.providerIconColor)
                }
                Text(provider.displayName)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if refreshService.refreshingProviders.contains(provider) {
                    ProgressView().controlSize(.small)
                } else if stale {
                    Text(settingsStore.localized("status.stale")).font(.caption2).foregroundStyle(.secondary)
                }
            }

            if windows.isEmpty || !mayShowData {
                Text(stale && !mayShowData
                     ? settingsStore.localized("status.stale")
                     : settingsStore.localized("status.usage_unavailable"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 2)
            } else {
                ForEach(Array(windows.enumerated()), id: \.element.id) { index, window in
                    if index > 0 { Divider() }
                    UsageView(limit: window, providerPreferences: preferences, settings: settings)
                }
            }

            if let error = refreshService.errorsByProvider[provider] {
                Text(localizedError(error, provider: provider))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func providerIcon(_ provider: AIProvider, color: ProviderIconColor) -> some View {
        if let image = ProviderIconAsset.image(for: provider, color: color) {
            Image(nsImage: image)
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: 15, height: 15)
                .accessibilityHidden(true)
        }
    }

    private var latestUpdate: Date? {
        refreshService.visibleProviders()
            .compactMap { refreshService.usageByProvider[$0] }
            .filter { !$0.windows.isEmpty }
            .map(\.lastUpdated)
            .max()
    }

    private func updatedText(_ date: Date) -> String {
        let time = date.formatted(
            Date.FormatStyle(date: .omitted, time: .shortened)
                .locale(settingsStore.settings.language.locale)
        )
        return String(
            format: settingsStore.localized("usage.updated_format"),
            locale: settingsStore.settings.language.locale,
            time
        )
    }

    private func localizedError(_ error: String, provider: AIProvider) -> String {
        if provider == .codex, AppLocationDiagnostics.isAppTranslocated {
            return settingsStore.localized("error.codex_translocated")
        }
        if provider == .claudeCode { return settingsStore.localized("error.claude_background") }
        if error.contains("Sign in") { return settingsStore.localized("error.codex_sign_in") }
        return settingsStore.localized("status.usage_unavailable")
    }

    private func quit() {
        if settingsStore.settings.confirmBeforeQuit {
            let alert = NSAlert()
            alert.messageText = settingsStore.localized("quit.title")
            alert.informativeText = settingsStore.localized("quit.info")
            alert.addButton(withTitle: settingsStore.localized("action.quit"))
            alert.addButton(withTitle: settingsStore.localized("action.cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        NSApplication.shared.terminate(nil)
    }
}

private struct CodexActivityListView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    let activities: [CodexActivity]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(activities.enumerated()), id: \.element.id) { index, activity in
                CodexActivityView(
                    activity: activity,
                    label: activityLabel(index: index, total: activities.count)
                )
                if index < activities.count - 1 {
                    Divider()
                }
            }
        }
    }

    private func activityLabel(index: Int, total: Int) -> String {
        let title = settingsStore.localized("activity.title")
        return total > 1 ? "\(title) \(index + 1)" : title
    }
}

private struct CodexActivityView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    let activity: CodexActivity
    let label: String

    var body: some View {
        Button {
            CodexActivityNavigator.open(activity)
        } label: {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: iconName)
                        .foregroundStyle(iconColor)
                        .frame(width: 15)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(label)
                                .font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Text(settingsStore.localized(activity.state.localizationKey))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        if let title = activity.title {
                            Text(title)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .foregroundStyle(.primary)
                        }
                        Text(elapsedText(at: context.date))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityText(at: context.date))
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHint(settingsStore.localized("activity.open_hint"))
    }

    private var iconName: String {
        switch activity.state {
        case .working: return "arrow.triangle.2.circlepath"
        case .waitingForApproval: return "checkmark.shield"
        case .waitingForInput: return "text.bubble"
        case .error: return "exclamationmark.triangle"
        }
    }

    private var iconColor: Color {
        switch activity.state {
        case .working: return .accentColor
        case .waitingForApproval, .waitingForInput: return .orange
        case .error: return .red
        }
    }

    private func elapsedText(at now: Date) -> String {
        guard let startedAt = activity.startedAt else {
            return settingsStore.localized("activity.elapsed_unavailable")
        }
        let seconds = max(0, Int(now.timeIntervalSince(startedAt)))
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainder = seconds % 60
        return String(
            format: settingsStore.localized("activity.elapsed_format"),
            locale: settingsStore.settings.language.locale,
            hours,
            minutes,
            remainder
        )
    }

    private func accessibilityText(at now: Date) -> String {
        let taskName = activity.title.map { ", \($0)" } ?? ""
        return "\(settingsStore.localized("activity.title"))\(taskName), \(settingsStore.localized(activity.state.localizationKey)), \(elapsedText(at: now))"
    }
}

enum PopoverLayoutModel {
    static func height(
        providerCount: Int,
        rowCount: Int,
        unavailableCount: Int,
        settings: AppSettings
    ) -> CGFloat {
        let rowHeight: CGFloat = {
            var value: CGFloat = 32
            if settings.showProgressBars && settings.progressBarStyle != .hidden { value += 10 }
            if settings.showResetTime, settings.resetTimeFormat != .hidden {
                value += settings.resetTimeFormat == .both ? 30 : 17
            }
            if settings.popoverSize == .comfortable { value += 10 }
            return value
        }()
        var value: CGFloat = 62
        value += CGFloat(providerCount) * 27
        value += CGFloat(rowCount) * rowHeight
        value += CGFloat(unavailableCount) * 28
        if settings.showLastUpdatedTime { value += 23 }
        if settings.showRefreshButton || settings.showSettingsButton || settings.showQuitButton { value += 30 }
        if settings.providerSeparators, providerCount > 1 { value += CGFloat(providerCount - 1) * 9 }
        return min(600, max(150, value))
    }
}
