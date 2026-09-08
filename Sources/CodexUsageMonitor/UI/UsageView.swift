import SwiftUI

struct UsageView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    let limit: UsageWindow
    let providerPreferences: ProviderPreferences
    let settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: settings.popoverSize == .compact ? 5 : 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(limit.type == .fiveHour ? "5H" : settingsStore.localized("limit.weekly"))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if settings.showRemainingPercentage {
                    Text(percentageText)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                if settings.showStatusLabels {
                    Text(levelText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                String(
                    format: settingsStore.localized("accessibility.usage_row"),
                    locale: settings.language.locale,
                    limit.type == .fiveHour ? "5H" : settingsStore.localized("limit.weekly"),
                    percentageText,
                    levelText
                )
            )

            if shouldShowProgressBar {
                ProgressView(value: limit.remainingPercent, total: 100)
                    .progressViewStyle(.linear)
                    .tint(color(for: level))
                    .controlSize(settings.progressBarStyle == .normal ? .regular : .mini)
                    .frame(height: settings.progressBarStyle == .normal ? 8 : 5)
            }

            if settings.showResetTime, providerPreferences.showResetTime {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text(resetText(at: context.date))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var percentageText: String {
        switch settings.percentagePrecision {
        case .integer: return limit.remainingPercent.percentageText
        case .oneDecimal: return String(format: "%.1f%%", limit.remainingPercent)
        }
    }

    private var shouldShowProgressBar: Bool {
        settings.showProgressBars
            && providerPreferences.showProgressBar
            && settings.progressBarStyle != .hidden
    }

    private var level: UsageLevel {
        if limit.remainingPercent <= Double(settings.criticalThreshold) { return .critical }
        if limit.remainingPercent <= Double(settings.warningThreshold) { return .warning }
        return .normal
    }

    private var levelText: String {
        settingsStore.localized("level.\(level.rawValue.lowercased())")
    }

    private func resetText(at now: Date) -> String {
        guard let resetDate = limit.resetDate else {
            return settingsStore.localized("reset.unavailable")
        }
        let seconds = max(0, resetDate.timeIntervalSince(now))
        let totalSeconds = Int(seconds)
        let days = totalSeconds / 86_400
        let hours = (totalSeconds % 86_400) / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let relative: String
        if days > 0 {
            relative = String(
                format: settingsStore.localized("reset.relative_days_hours_minutes"),
                locale: settings.language.locale,
                days,
                hours,
                minutes
            )
        } else if hours > 0 {
            relative = String(
                format: settingsStore.localized("reset.relative_hours_minutes"),
                locale: settings.language.locale,
                hours,
                minutes
            )
        } else {
            relative = String(
                format: settingsStore.localized("reset.relative_minutes"),
                locale: settings.language.locale,
                minutes
            )
        }
        let date = resetDate.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened)
                .locale(settings.language.locale)
        )
        let absolute = String(
            format: settingsStore.localized("reset.absolute"),
            locale: settings.language.locale,
            date
        )
        switch settings.resetTimeFormat {
        case .relative: return relative
        case .absolute: return absolute
        case .both: return "\(relative)\n\(absolute)"
        }
    }

    private func color(for level: UsageLevel) -> Color {
        switch level {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }
}
