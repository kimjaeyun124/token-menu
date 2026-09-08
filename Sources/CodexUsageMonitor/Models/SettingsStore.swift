import Foundation
import SwiftUI

enum MenuBarProviderChoice: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic, codex, claudeCode, both
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .codex: return "Codex"
        case .claudeCode: return "Claude Code"
        case .both: return "Codex + Claude Code"
        }
    }
    var provider: AIProvider? {
        switch self {
        case .automatic: return nil
        case .codex: return .codex
        case .claudeCode: return .claudeCode
        case .both: return nil
        }
    }
}

enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case systemDefault, korean, english
    var id: String { rawValue }
    var locale: Locale {
        switch self {
        case .systemDefault: return .current
        case .korean: return Locale(identifier: "ko")
        case .english: return Locale(identifier: "en")
        }
    }

    var localizationIdentifier: String {
        switch self {
        case .systemDefault:
            return Locale.current.language.languageCode?.identifier == "ko" ? "ko" : "en"
        case .korean: return "ko"
        case .english: return "en"
        }
    }
}

enum ProviderIdentification: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, icon, name, iconAndName
    var id: String { rawValue }
}

enum ProviderIconColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case white, black, accent, secondary

    var id: String { rawValue }

    var localizationKey: String { "option.icon_color_\(rawValue)" }

    var swiftUIColor: Color {
        switch self {
        case .white: return .white
        case .black: return .black
        case .accent: return .accentColor
        case .secondary: return .secondary
        }
    }
}

enum MenuBarLimitChoice: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic, fiveHour, weekly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .fiveHour: return "5H"
        case .weekly: return "Weekly"
        }
    }
}

enum MenuBarFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case pipe, space, dot, percentageOnly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pipe: return "5H | 28%"
        case .space: return "5H 28%"
        case .dot: return "5H · 28%"
        case .percentageOnly: return "28%"
        }
    }
}

enum PercentagePrecision: String, Codable, CaseIterable, Identifiable, Sendable {
    case integer, oneDecimal
    var id: String { rawValue }
    var title: String { self == .integer ? "Integer" : "1 decimal" }
}

enum UnavailableDisplay: String, Codable, CaseIterable, Identifiable, Sendable {
    case dashes, notAvailable, hidden
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dashes: return "--%"
        case .notAvailable: return "N/A"
        case .hidden: return "Hidden"
        }
    }
}

enum DurationUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case seconds, minutes, hours
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var seconds: TimeInterval {
        switch self {
        case .seconds: return 1
        case .minutes: return 60
        case .hours: return 3_600
        }
    }
}

struct RefreshDuration: Codable, Equatable, Sendable {
    var value: Int
    var unit: DurationUnit

    var rawSeconds: TimeInterval { TimeInterval(value) * unit.seconds }
    var isValid: Bool { (30...86_400).contains(rawSeconds) }
    var clampedSeconds: TimeInterval { min(86_400, max(30, rawSeconds)) }

    static let fiveMinutes = RefreshDuration(value: 5, unit: .minutes)
    static let thirtySeconds = RefreshDuration(value: 30, unit: .seconds)
    static let fifteenMinutes = RefreshDuration(value: 15, unit: .minutes)

    static func from(seconds: Int) -> RefreshDuration {
        if seconds % 3_600 == 0 { return RefreshDuration(value: seconds / 3_600, unit: .hours) }
        if seconds % 60 == 0 { return RefreshDuration(value: seconds / 60, unit: .minutes) }
        return RefreshDuration(value: seconds, unit: .seconds)
    }
}

enum ResetTimeFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case relative, absolute, both
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum PopoverSize: String, Codable, CaseIterable, Identifiable, Sendable {
    case compact, comfortable
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum ProgressBarStyleChoice: String, Codable, CaseIterable, Identifiable, Sendable {
    case normal, thin, hidden
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum PopoverWidth: String, Codable, CaseIterable, Identifiable, Sendable {
    case small, medium, large
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var points: CGFloat {
        switch self {
        case .small: return 280
        case .medium: return 320
        case .large: return 360
        }
    }
}

enum ShortcutKey: String, Codable, CaseIterable, Identifiable, Sendable {
    case c = "C", m = "M", u = "U"
    var id: String { rawValue }
}

struct ProviderPreferences: Codable, Equatable, Sendable {
    var enabled = true
    var showInPopover = true
    var includeInManualRefresh = true
    var includeInAutomaticRefresh = true
    var showFiveHour = true
    var showWeekly = true
    var showResetTime = true
    var showProgressBar = true
    var useGlobalRefreshInterval = true
    var customRefreshInterval = RefreshDuration.fiveMinutes
    var notificationsEnabled = true
}

struct AppSettings: Codable, Equatable, Sendable {
    var schemaVersion = 3

    var launchAtLogin = false
    var language = AppLanguage.systemDefault
    var openPopoverAfterLaunch = false
    var startHiddenAtLogin = true
    var confirmBeforeQuit = false
    var globalShortcutEnabled = false
    var shortcutKey = ShortcutKey.c

    var menuBarProvider = MenuBarProviderChoice.automatic
    var menuBarLimit = MenuBarLimitChoice.automatic
    var menuBarFormat = MenuBarFormat.pipe
    var showProviderName = false
    var providerIdentification = ProviderIdentification.icon
    var providerIconColor = ProviderIconColor.white
    var percentagePrecision = PercentagePrecision.integer
    var unavailableDisplay = UnavailableDisplay.dashes

    var codex = ProviderPreferences()
    var claudeCode = ProviderPreferences()
    var providerOrder = AIProvider.allCases

    var showRemainingPercentage = true
    var showResetTime = true
    var showProgressBars = true
    var showLastUpdatedTime = true
    var showStatusLabels = false
    var resetTimeFormat = ResetTimeFormat.relative

    var automaticRefresh = true
    var globalRefreshInterval = RefreshDuration.fiveMinutes
    var refreshOnLaunch = true
    var refreshWhenPopoverOpens = true
    var refreshAfterWake = true
    var refreshAfterNetworkReconnect = true
    var refreshWhenSettingsChange = false
    var staleDataThreshold = RefreshDuration.fifteenMinutes
    var retryFailedRefresh = true
    var retryDelay = RefreshDuration.thirtySeconds
    var retryCount = 2

    var notificationsEnabled = false
    var fiveHourNotificationThreshold = 20
    var weeklyNotificationThreshold = 20

    var popoverSize = PopoverSize.compact
    var progressBarStyle = ProgressBarStyleChoice.thin
    var providerSeparators = true
    var showProviderIcons = true
    var popoverWidth = PopoverWidth.medium
    var showRefreshButton = true
    var showSettingsButton = true
    var showQuitButton = true
    var warningThreshold = 50
    var criticalThreshold = 20

    var keepLastSuccessfulUsageOnError = true
    var showStaleData = true
    var backgroundRefresh = true
    var pauseAutomaticRefreshOnBattery = false
    var pauseRefreshDuringLowPowerMode = false
    var refreshImmediatelyAfterSettingsChange = false

    func preferences(for provider: AIProvider) -> ProviderPreferences {
        provider == .codex ? codex : claudeCode
    }

    mutating func setPreferences(_ preferences: ProviderPreferences, for provider: AIProvider) {
        if provider == .codex { codex = preferences } else { claudeCode = preferences }
    }

    func refreshInterval(for provider: AIProvider) -> TimeInterval {
        let preferences = preferences(for: provider)
        return preferences.useGlobalRefreshInterval
            ? globalRefreshInterval.clampedSeconds
            : preferences.customRefreshInterval.clampedSeconds
    }

    var thresholdsAreValid: Bool {
        (1...100).contains(warningThreshold)
            && (0...warningThreshold).contains(criticalThreshold)
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    static let storageKey = "appSettings.v1"

    @Published var settings: AppSettings {
        didSet {
            persist()
            revision += 1
        }
    }
    @Published private(set) var revision = 0

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = Self.decodeWithDefaults(data) {
            settings = decoded
        } else {
            settings = Self.migrateLegacySettings(from: defaults)
        }
    }

    func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { self.settings[keyPath: keyPath] = $0 }
        )
    }

    func preferences(for provider: AIProvider) -> ProviderPreferences {
        settings.preferences(for: provider)
    }

    func updatePreferences(for provider: AIProvider, _ update: (inout ProviderPreferences) -> Void) {
        var preferences = settings.preferences(for: provider)
        update(&preferences)
        settings.setPreferences(preferences, for: provider)
    }

    func moveProvider(from offsets: IndexSet, to destination: Int) {
        settings.providerOrder.move(fromOffsets: offsets, toOffset: destination)
    }

    func resetToDefaults() {
        settings = AppSettings()
    }

    func localized(_ key: String) -> String {
        LocalizationCatalog.value(
            for: key,
            language: settings.language.localizationIdentifier
        )
    }

    func validateDurations() {
        if !settings.globalRefreshInterval.isValid {
            settings.globalRefreshInterval = .from(seconds: Int(settings.globalRefreshInterval.clampedSeconds))
        }
        if !settings.staleDataThreshold.isValid {
            settings.staleDataThreshold = .from(seconds: Int(settings.staleDataThreshold.clampedSeconds))
        }
        if !settings.retryDelay.isValid {
            settings.retryDelay = .from(seconds: Int(settings.retryDelay.clampedSeconds))
        }
        for provider in AIProvider.allCases {
            var preferences = settings.preferences(for: provider)
            if !preferences.customRefreshInterval.isValid {
                preferences.customRefreshInterval = .from(
                    seconds: Int(preferences.customRefreshInterval.clampedSeconds)
                )
                settings.setPreferences(preferences, for: provider)
            }
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private static func migrateLegacySettings(from defaults: UserDefaults) -> AppSettings {
        var settings = AppSettings()
        if let rawProvider = defaults.string(forKey: "selectedProvider"),
           let provider = AIProvider(rawValue: rawProvider) {
            settings.menuBarProvider = provider == .codex ? .codex : .claudeCode
        }
        if let interval = defaults.object(forKey: "refreshInterval") as? NSNumber {
            settings.globalRefreshInterval = .from(seconds: interval.intValue)
        }
        if defaults.object(forKey: "globalShortcutEnabled") != nil {
            settings.globalShortcutEnabled = defaults.bool(forKey: "globalShortcutEnabled")
        }
        return settings
    }

    private static func decodeWithDefaults(_ storedData: Data) -> AppSettings? {
        guard
            let defaultData = try? JSONEncoder().encode(AppSettings()),
            var defaultObject = try? JSONSerialization.jsonObject(with: defaultData) as? [String: Any],
            let storedObject = try? JSONSerialization.jsonObject(with: storedData) as? [String: Any]
        else { return nil }
        merge(storedObject, into: &defaultObject)
        let storedVersion = storedObject["schemaVersion"] as? Int ?? 1
        // Version 2 makes the supplied provider artwork visible in the menu bar
        // by default. Existing version-1 data used the old symbol-only default.
        if storedVersion < 2 {
            defaultObject["schemaVersion"] = 2
            defaultObject["providerIdentification"] = ProviderIdentification.icon.rawValue
        }
        // Version 3 adds an explicit icon tint preference. White is the
        // high-contrast default for the dark menu bar and usage popover.
        if storedVersion < 3 {
            defaultObject["schemaVersion"] = 3
            defaultObject["providerIconColor"] = ProviderIconColor.white.rawValue
        }
        guard let mergedData = try? JSONSerialization.data(withJSONObject: defaultObject) else { return nil }
        return try? JSONDecoder().decode(AppSettings.self, from: mergedData)
    }

    private static func merge(_ stored: [String: Any], into defaults: inout [String: Any]) {
        for (key, value) in stored {
            if let nestedStored = value as? [String: Any],
               var nestedDefault = defaults[key] as? [String: Any] {
                merge(nestedStored, into: &nestedDefault)
                defaults[key] = nestedDefault
            } else {
                defaults[key] = value
            }
        }
    }
}

private enum LocalizationCatalog {
    private struct Catalog: Decodable {
        let sourceLanguage: String
        let strings: [String: Entry]
    }

    private struct Entry: Decodable {
        let localizations: [String: Localization]?
    }

    private struct Localization: Decodable {
        let stringUnit: StringUnit
    }

    private struct StringUnit: Decodable {
        let value: String
    }

    private static let catalog: Catalog? = {
        guard let resourceBundle = LocalizationCatalog.resourceBundle,
              let url = resourceBundle.url(forResource: "Localizable", withExtension: "xcstrings"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Catalog.self, from: data)
    }()

    private static let resourceBundle: Bundle? = {
        // Packaged app resources live in Contents/Resources. Looking there
        // first avoids a potentially slow Bundle.module fallback scan during
        // menu-bar startup, while the fallback keeps SwiftPM tests working.
        let bundleName = "CodexUsageMonitor_CodexUsageMonitor.bundle"
        if let resourceURL = Bundle.main.resourceURL,
           let bundle = Bundle(url: resourceURL.appendingPathComponent(bundleName)) {
            return bundle
        }
        return Bundle.module
    }()

    static func value(for key: String, language: String) -> String {
        guard let catalog, let entry = catalog.strings[key] else { return key }
        return entry.localizations?[language]?.stringUnit.value
            ?? entry.localizations?[catalog.sourceLanguage]?.stringUnit.value
            ?? key
    }
}
