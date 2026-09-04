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

enum UsageSelection: String, CaseIterable, Identifiable {
    case fiveHour
    case weekly
    case lowest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fiveHour: return "5-Hour %"
        case .weekly: return "Weekly %"
        case .lowest: return "Lowest %"
        }
    }

    func value(in usage: CodexUsage) -> Double? {
        switch self {
        case .fiveHour: return usage.fiveHourRemainingPercent
        case .weekly: return usage.weeklyRemainingPercent
        case .lowest: return usage.lowestRemainingPercent
        }
    }
}

enum DockBadgeSelection: String, CaseIterable, Identifiable {
    case fiveHour
    case weekly
    case lowest
    case disabled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fiveHour: return "5-Hour %"
        case .weekly: return "Weekly %"
        case .lowest: return "Lowest %"
        case .disabled: return "Off"
        }
    }

    func value(in usage: CodexUsage) -> Double? {
        switch self {
        case .fiveHour: return usage.fiveHourRemainingPercent
        case .weekly: return usage.weeklyRemainingPercent
        case .lowest: return usage.lowestRemainingPercent
        case .disabled: return nil
        }
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
    static let dockBadgeSelection = "dockBadgeSelection"
    static let refreshInterval = "refreshInterval"
    static let notificationThreshold = "notificationThreshold"
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

