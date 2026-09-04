import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var refreshService: UsageRefreshService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Codex Usage")
                .font(.title2.bold())

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
            }

            Divider()
            HStack {
                Button("Settings…") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 340)
    }
}

