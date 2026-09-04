import SwiftUI

struct UsageView: View {
    let title: String
    let remainingPercent: Double?
    let resetDate: Date?
    let compactReset: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                Spacer()
                if let remainingPercent {
                    StatusLabel(level: UsageLevel(remainingPercent: remainingPercent))
                }
            }

            if let remainingPercent {
                Text("\(remainingPercent.percentageText) remaining")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .accessibilityLabel("\(title), \(remainingPercent.percentageText) remaining")
                ProgressView(value: remainingPercent, total: 100)
                    .progressViewStyle(.linear)
                    .tint(color(for: UsageLevel(remainingPercent: remainingPercent)))
            } else {
                Text("Unavailable")
                    .font(.title2.weight(.semibold))
                ProgressView(value: 0, total: 100)
                    .progressViewStyle(.linear)
            }

            TimelineView(.periodic(from: .now, by: 60)) { context in
                Text(resetText(at: context.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private func resetText(at now: Date) -> String {
        guard let resetDate else { return "Reset unavailable" }
        if compactReset {
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

private struct StatusLabel: View {
    let level: UsageLevel

    var body: some View {
        Label(level.rawValue, systemImage: level.symbolName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
    }

    private var color: Color {
        switch level {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }
}

