import AppKit
import SwiftUI

struct UsageWindowView: View {
    @EnvironmentObject private var refreshService: UsageRefreshService
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var visibility: AppVisibilityController

    var body: some View {
        let providers = refreshService.visibleProviders()
        let settings = settingsStore.settings

        VStack(alignment: .leading, spacing: settings.popoverSize == .compact ? 9 : 13) {
            Text(settingsStore.localized("app.title"))
                .font(.system(size: 16, weight: .semibold))

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
            if settings.showResetTime { value += settings.resetTimeFormat == .both ? 30 : 17 }
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
