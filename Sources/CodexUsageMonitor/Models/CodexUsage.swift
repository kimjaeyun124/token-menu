import Foundation

enum AIProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    case codex
    case claudeCode

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .claudeCode: return "Claude Code"
        }
    }

    var menuBarName: String { self == .codex ? "Codex" : "Claude" }
}

enum UsageWindowType: String, Identifiable, Sendable {
    case fiveHour
    case weekly

    var id: String { rawValue }
    var displayName: String { self == .fiveHour ? "5-Hour" : "Weekly" }
    var shortName: String { self == .fiveHour ? "5H" : "Weekly" }
}

struct UsageWindow: Identifiable, Equatable, Sendable {
    let type: UsageWindowType
    let remainingPercent: Double
    let resetDate: Date?

    var id: UsageWindowType { type }
    var displayName: String { type.displayName }
    var shortName: String { type.shortName }
}

struct AIUsage: Equatable, Sendable {
    let provider: AIProvider
    let windows: [UsageWindow]
    let lastUpdated: Date
    let source: String

    func window(_ type: UsageWindowType) -> UsageWindow? {
        windows.first { $0.type == type }
    }

    var fiveHourRemainingPercent: Double? { window(.fiveHour)?.remainingPercent }
    var weeklyRemainingPercent: Double? { window(.weekly)?.remainingPercent }
    var fiveHourResetDate: Date? { window(.fiveHour)?.resetDate }
    var weeklyResetDate: Date? { window(.weekly)?.resetDate }
    var lowestRemainingPercent: Double? { windows.map(\.remainingPercent).min() }

    static func unavailable(
        provider: AIProvider,
        at date: Date = Date(),
        source: String = "Unavailable"
    ) -> AIUsage {
        AIUsage(provider: provider, windows: [], lastUpdated: date, source: source)
    }
}

struct MenuBarPresentation: Equatable, Sendable {
    struct Segment: Equatable, Sendable {
        let provider: AIProvider
        let label: String
        let remainingPercent: Double?
        let text: String
    }

    let provider: AIProvider?
    let label: String
    let remainingPercent: Double?
    let text: String
    let segments: [Segment]

    static func resolve(
        usages: [AIProvider: AIUsage],
        settings: AppSettings
    ) -> MenuBarPresentation {
        let enabledProviders = settings.providerOrder.filter {
            settings.preferences(for: $0).enabled
        }
        let selectedProviders: [AIProvider]
        switch settings.menuBarProvider {
        case .automatic:
            selectedProviders = enabledProviders.first { !(usages[$0]?.windows.isEmpty ?? true) }
                .map { [$0] } ?? Array(enabledProviders.prefix(1))
        case .codex:
            selectedProviders = settings.codex.enabled ? [.codex] : []
        case .claudeCode:
            selectedProviders = settings.claudeCode.enabled ? [.claudeCode] : []
        case .both:
            selectedProviders = enabledProviders
        }

        let segments = selectedProviders.map {
            resolveSegment(provider: $0, usage: usages[$0], settings: settings)
        }
        guard !segments.isEmpty else {
            return unavailable(label: "AI", settings: settings)
        }
        let visibleSegments = segments.filter { !$0.text.isEmpty }
        let text = visibleSegments.map(\.text).joined(separator: " / ")
        return MenuBarPresentation(
            provider: segments.count == 1 ? segments[0].provider : nil,
            label: segments.count == 1 ? segments[0].label : "AI",
            remainingPercent: segments.count == 1 ? segments[0].remainingPercent : nil,
            text: text,
            segments: visibleSegments
        )
    }

    private static func resolveSegment(
        provider: AIProvider,
        usage: AIUsage?,
        settings: AppSettings
    ) -> Segment {
        guard let usage, !usage.windows.isEmpty else {
            return unavailableSegment(label: "AI", provider: provider, settings: settings)
        }

        let window: UsageWindow?
        let missingLabel: String
        switch settings.menuBarLimit {
        case .automatic:
            window = usage.window(.fiveHour) ?? usage.window(.weekly)
            missingLabel = "AI"
        case .fiveHour:
            window = usage.window(.fiveHour)
            missingLabel = "5H"
        case .weekly:
            window = usage.window(.weekly)
            missingLabel = "Weekly"
        }

        guard let window else {
            return unavailableSegment(label: missingLabel, provider: provider, settings: settings)
        }
        let percentage = formattedPercentage(
            window.remainingPercent,
            precision: settings.percentagePrecision
        )
        return Segment(
            provider: provider,
            label: window.shortName,
            remainingPercent: window.remainingPercent,
            text: compose(
                label: window.shortName,
                value: percentage,
                provider: provider,
                settings: settings
            )
        )
    }

    private static func unavailable(
        label: String,
        provider: AIProvider? = nil,
        settings: AppSettings
    ) -> MenuBarPresentation {
        guard settings.unavailableDisplay != .hidden else {
            return MenuBarPresentation(
                provider: provider,
                label: label,
                remainingPercent: nil,
                text: "",
                segments: []
            )
        }
        let value = settings.unavailableDisplay == .dashes ? "--%" : "N/A"
        let segments = provider.map {
            [Segment(
                provider: $0,
                label: label,
                remainingPercent: nil,
                text: compose(label: label, value: value, provider: $0, settings: settings)
            )]
        } ?? []
        return MenuBarPresentation(
            provider: provider,
            label: label,
            remainingPercent: nil,
            text: compose(label: label, value: value, provider: provider, settings: settings),
            segments: segments
        )
    }

    private static func unavailableSegment(
        label: String,
        provider: AIProvider,
        settings: AppSettings
    ) -> Segment {
        guard settings.unavailableDisplay != .hidden else {
            return Segment(provider: provider, label: label, remainingPercent: nil, text: "")
        }
        let value = settings.unavailableDisplay == .dashes ? "--%" : "N/A"
        return Segment(
            provider: provider,
            label: label,
            remainingPercent: nil,
            text: compose(label: label, value: value, provider: provider, settings: settings)
        )
    }

    private static func compose(
        label: String,
        value: String,
        provider: AIProvider?,
        settings: AppSettings
    ) -> String {
        let core: String
        switch settings.menuBarFormat {
        case .pipe: core = "\(label) | \(value)"
        case .space: core = "\(label) \(value)"
        case .dot: core = "\(label) · \(value)"
        case .percentageOnly: core = value
        }
        let identification: ProviderIdentification = settings.showProviderName
            ? (settings.providerIdentification == .icon
                ? .iconAndName
                : (settings.providerIdentification == .none ? .name : settings.providerIdentification))
            : settings.providerIdentification
        if identification == .name || identification == .iconAndName, let provider {
            return "\(provider.menuBarName) · \(core)"
        }
        return core
    }

    private static func formattedPercentage(
        _ value: Double,
        precision: PercentagePrecision
    ) -> String {
        switch precision {
        case .integer: return "\(Int(value.rounded()))%"
        case .oneDecimal: return String(format: "%.1f%%", value)
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
