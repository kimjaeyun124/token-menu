import AppKit
import SwiftUI

struct UsageWindowView: View {
    @EnvironmentObject private var refreshService: UsageRefreshService
    @EnvironmentObject private var visibility: AppVisibilityController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Codex Usage")
                .font(.system(size: 17, weight: .semibold))

            if refreshService.usage.availableLimits.isEmpty {
                Text("Usage unavailable")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(refreshService.usage.availableLimits.enumerated()), id: \.element.id) { index, limit in
                    if index > 0 {
                        Divider()
                    }
                    UsageView(limit: limit)
                }
            }

            if let errorMessage = refreshService.errorMessage,
               refreshService.usage.availableLimits.isEmpty {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Text("Updated \(refreshService.usage.lastUpdated.formatted(date: .omitted, time: .shortened))")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            HStack {
                Button("Refresh") {
                    Task { await refreshService.refresh() }
                }
                .disabled(refreshService.isRefreshing)
                .keyboardShortcut("r")

                Spacer()

                if #available(macOS 14.0, *) {
                    SettingsLink { Text("Settings") }
                } else {
                    Button("Settings") { visibility.showSettings() }
                }

                Spacer()

                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12))
        }
        .padding(14)
        .frame(width: 330)
    }
}
