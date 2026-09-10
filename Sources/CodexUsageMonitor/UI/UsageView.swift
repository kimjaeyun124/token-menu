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

            if settings.showResetTime, providerPreferences.showResetTime, settings.resetTimeFormat != .hidden {
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
        PercentageFormatter.string(
            for: limit.remainingPercent,
            precision: settings.percentagePrecision
        ) ?? PercentageFormatter.unavailable(settings.unavailableDisplay)
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
        let relative = relativeResetText(days: days, hours: hours, minutes: minutes)
        let absolute = absoluteResetText(resetDate, now: now)
        switch settings.resetTimeFormat {
        case .relative: return relative
        case .absolute: return absolute
        case .both: return "\(relative)\n\(absolute)"
        case .hidden: return ""
        }
    }

    private func relativeResetText(days: Int, hours: Int, minutes: Int) -> String {
        let key: String
        let arguments: [CVarArg]
        if days > 0 {
            if hours > 0, minutes > 0 { key = "reset.relative_days_hours_minutes"; arguments = [days, hours, minutes] }
            else if hours > 0 { key = "reset.relative_days_hours"; arguments = [days, hours] }
            else if minutes > 0 { key = "reset.relative_days_minutes"; arguments = [days, minutes] }
            else { key = "reset.relative_days"; arguments = [days] }
        } else if hours > 0 {
            if minutes > 0 { key = "reset.relative_hours_minutes"; arguments = [hours, minutes] }
            else { key = "reset.relative_hours"; arguments = [hours] }
        } else {
            key = "reset.relative_minutes"
            arguments = [minutes]
        }
        return String(format: settingsStore.localized(key), locale: settings.language.locale, arguments: arguments)
    }

    private func absoluteResetText(_ resetDate: Date, now: Date) -> String {
        let locale = settings.language.locale
        let calendar = Calendar(identifier: .gregorian)
        let dayOffset = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: resetDate)
        ).day ?? 0
        let timeFormatter = DateFormatter()
        timeFormatter.locale = locale
        timeFormatter.setLocalizedDateFormatFromTemplate("jmm")
        let time = timeFormatter.string(from: resetDate)
        if dayOffset == 0 {
            return String(format: settingsStore.localized("reset.absolute_today"), locale: locale, time)
        }
        if dayOffset == 1 {
            return String(format: settingsStore.localized("reset.absolute_tomorrow"), locale: locale, time)
        }
        let dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.setLocalizedDateFormatFromTemplate("MMMd")
        return String(
            format: settingsStore.localized("reset.absolute_date"),
            locale: locale,
            dateFormatter.string(from: resetDate),
            time
        )
    }

    private func color(for level: UsageLevel) -> Color {
        switch level {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }
}
