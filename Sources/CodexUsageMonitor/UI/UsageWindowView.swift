import AppKit
import SwiftUI

struct UsageWindowView: View {
    @EnvironmentObject private var refreshService: UsageRefreshService
    @EnvironmentObject private var visibility: AppVisibilityController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Codex Usage")
                .font(.largeTitle.bold())

            UsageView(
                title: "5-Hour Limit",
                remainingPercent: refreshService.usage.fiveHourRemainingPercent,
                resetDate: refreshService.usage.fiveHourResetDate,
                compactReset: true
            )
            UsageView(
                title: "Weekly Limit",
                remainingPercent: refreshService.usage.weeklyRemainingPercent,
                resetDate: refreshService.usage.weeklyResetDate,
                compactReset: false
            )

            if let errorMessage = refreshService.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Last updated \(refreshService.usage.lastUpdated.formatted(date: .omitted, time: .shortened))")
                    Text(refreshService.usage.source)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await refreshService.refresh() }
                } label: {
                    if refreshService.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(refreshService.isRefreshing)
                .keyboardShortcut("r")
            }

            Divider()
            HStack {
                if #available(macOS 14.0, *) {
                    SettingsLink { Text("Settings…") }
                        .keyboardShortcut(",")
                } else {
                    Button("Settings…") { visibility.showSettings() }
                        .keyboardShortcut(",")
                }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(20)
        .frame(minWidth: 380, idealWidth: 410, minHeight: 560, idealHeight: 610)
    }
}
