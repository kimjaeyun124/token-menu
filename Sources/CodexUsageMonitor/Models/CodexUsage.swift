import Foundation

struct CodexUsage: Equatable, Sendable {
    let fiveHourRemainingPercent: Double?
    let weeklyRemainingPercent: Double?
    let fiveHourResetDate: Date?
    let weeklyResetDate: Date?
    let lastUpdated: Date
    let source: String

    var lowestRemainingPercent: Double? {
        [fiveHourRemainingPercent, weeklyRemainingPercent].compactMap { $0 }.min()
    }

    var availableLimits: [AvailableUsageLimit] {
        var limits: [AvailableUsageLimit] = []
        if let fiveHourRemainingPercent {
            limits.append(AvailableUsageLimit(
                kind: .fiveHour,
                remainingPercent: fiveHourRemainingPercent,
                resetDate: fiveHourResetDate
            ))
        }
        if let weeklyRemainingPercent {
            limits.append(AvailableUsageLimit(
                kind: .weekly,
                remainingPercent: weeklyRemainingPercent,
                resetDate: weeklyResetDate
            ))
        }
        return limits
    }

    static func unavailable(at date: Date = Date(), source: String = "Unavailable") -> CodexUsage {
        CodexUsage(
            fiveHourRemainingPercent: nil,
            weeklyRemainingPercent: nil,
            fiveHourResetDate: nil,
            weeklyResetDate: nil,
            lastUpdated: date,
            source: source
        )
    }
}

enum UsageWindowKind: String, Identifiable, Sendable {
    case fiveHour
    case weekly

    var id: String { rawValue }
    var title: String { self == .fiveHour ? "5H" : "Weekly" }
}

struct AvailableUsageLimit: Identifiable, Equatable, Sendable {
    let kind: UsageWindowKind
    let remainingPercent: Double
    let resetDate: Date?

    var id: UsageWindowKind { kind }
}

struct MenuBarPresentation: Equatable, Sendable {
    let label: String
    let remainingPercent: Double?

    var text: String {
        guard let remainingPercent else { return "Codex --%" }
        return "\(label) \(remainingPercent.percentageText)"
    }
}

enum MenuBarSelection: String, CaseIterable, Identifiable {
    case automatic
    case fiveHour
    case weekly
    case lowest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .fiveHour: return "5-Hour %"
        case .weekly: return "Weekly %"
        case .lowest: return "Lowest %"
        }
    }

    func presentation(in usage: CodexUsage) -> MenuBarPresentation {
        switch self {
        case .automatic, .fiveHour:
            if let value = usage.fiveHourRemainingPercent {
                return MenuBarPresentation(label: "5H", remainingPercent: value)
            }
            if let value = usage.weeklyRemainingPercent {
                return MenuBarPresentation(label: "Weekly", remainingPercent: value)
            }
        case .weekly:
            if let value = usage.weeklyRemainingPercent {
                return MenuBarPresentation(label: "Weekly", remainingPercent: value)
            }
            if let value = usage.fiveHourRemainingPercent {
                return MenuBarPresentation(label: "5H", remainingPercent: value)
            }
        case .lowest:
            let available = usage.availableLimits
            if let lowest = available.min(by: { $0.remainingPercent < $1.remainingPercent }) {
                return MenuBarPresentation(
                    label: available.count == 1 ? lowest.kind.title : "Low",
                    remainingPercent: lowest.remainingPercent
                )
            }
        }
        return MenuBarPresentation(label: "Codex", remainingPercent: nil)
    }
}

enum UsageLevel: String, Equatable {
    case normal = "Normal"
    case warning = "Warning"
    case critical = "Critical"

    init(remainingPercent: Double) {
        if remainingPercent <= 20 {
            self = .critical
        } else if remainingPercent <= 50 {
            self = .warning
        } else {
            self = .normal
        }
    }

    var symbolName: String {
        switch self {
        case .normal: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }
}

enum RefreshInterval: Int, CaseIterable, Identifiable {
    case oneMinute = 60
    case fiveMinutes = 300
    case tenMinutes = 600
    case thirtyMinutes = 1_800

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .oneMinute: return "1 minute"
        case .fiveMinutes: return "5 minutes"
        case .tenMinutes: return "10 minutes"
        case .thirtyMinutes: return "30 minutes"
        }
    }
}

enum NotificationThreshold: Int, CaseIterable, Identifiable {
    case off = 0
    case fifty = 50
    case twenty = 20
    case ten = 10

    var id: Int { rawValue }
    var title: String { self == .off ? "Off" : "\(rawValue)%" }
}

enum SettingsKey {
    static let menuBarSelection = "menuBarSelection"
    static let refreshInterval = "refreshInterval"
    static let notificationThreshold = "notificationThreshold"
    static let globalShortcutEnabled = "globalShortcutEnabled"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            menuBarSelection: MenuBarSelection.automatic.rawValue,
            refreshInterval: RefreshInterval.fiveMinutes.rawValue,
            notificationThreshold: NotificationThreshold.twenty.rawValue,
            globalShortcutEnabled: true
        ])
    }
}

extension Double {
    var percentageText: String { "\(Int(rounded()))%" }

    static func remaining(fromUsedPercent usedPercent: Double) -> Double? {
        guard usedPercent.isFinite, (0...100).contains(usedPercent) else { return nil }
        let remainingPercent = 100 - usedPercent
        guard remainingPercent.isFinite, (0...100).contains(remainingPercent) else { return nil }
        return remainingPercent
    }
}
