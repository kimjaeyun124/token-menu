import SwiftUI

struct UsageView: View {
    let limit: AvailableUsageLimit

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(limit.kind.title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(limit.remainingPercent.percentageText)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "\(limit.kind.title), \(limit.remainingPercent.percentageText) remaining"
            )

            ProgressView(value: limit.remainingPercent, total: 100)
                .progressViewStyle(.linear)
                .tint(color(for: UsageLevel(remainingPercent: limit.remainingPercent)))
                .controlSize(.mini)
                .frame(height: 5)

            TimelineView(.periodic(from: .now, by: 60)) { context in
                Text(resetText(at: context.date))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func resetText(at now: Date) -> String {
        guard let resetDate = limit.resetDate else { return "Reset unavailable" }
        if limit.kind == .fiveHour {
            let seconds = max(0, resetDate.timeIntervalSince(now))
            let hours = Int(seconds) / 3_600
            let minutes = (Int(seconds) % 3_600) / 60
            return "Resets in \(hours)h \(minutes)m"
        }
        return "Resets \(resetDate.formatted(date: .abbreviated, time: .shortened))"
    }

    private func color(for level: UsageLevel) -> Color {
        switch level {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }
}
