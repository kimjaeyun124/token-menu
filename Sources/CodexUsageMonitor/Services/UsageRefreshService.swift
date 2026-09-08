import Combine
import Foundation
import OSLog
import UserNotifications

enum RefreshReason: Sendable {
    case launch, manual, automatic, popover, wake, network, settings, diagnostics
}

struct ProviderDiagnostics: Equatable, Sendable {
    var installed = false
    var connected = false
    var version = "Not installed"
    var lastRefresh: Date?
    var lastSuccessfulRefresh: Date?
    var source = "Unavailable"
    var status = "Not checked"
}

@MainActor
protocol RefreshScheduling: AnyObject {
    func schedule(every interval: TimeInterval, action: @escaping @MainActor () async -> Void)
    func invalidate()
}

@MainActor
final class TimerRefreshScheduler: RefreshScheduling {
    private var timer: Timer?

    func schedule(every interval: TimeInterval, action: @escaping @MainActor () async -> Void) {
        invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in await action() }
        }
        timer?.tolerance = min(15, interval * 0.1)
    }

    func invalidate() {
        timer?.invalidate()
        timer = nil
    }
}

@MainActor
final class UsageRefreshService: ObservableObject {
    @Published private(set) var usageByProvider: [AIProvider: AIUsage]
    @Published private(set) var errorsByProvider: [AIProvider: String] = [:]
    @Published private(set) var refreshingProviders = Set<AIProvider>()
    @Published private(set) var diagnosticsByProvider: [AIProvider: ProviderDiagnostics]
    @Published private(set) var scheduledInterval: TimeInterval?

    var isRefreshing: Bool { !refreshingProviders.isEmpty }
    var menuBarPresentation: MenuBarPresentation {
        .resolve(usages: usageByProvider, settings: settingsStore.settings)
    }

    private let providers: [AIProvider: any AIUsageProvider]
    private let scheduler: any RefreshScheduling
    let settingsStore: SettingsStore
    private var hasStarted = false
    private var lastAttemptByProvider: [AIProvider: Date] = [:]
    private var previousUsageByProvider: [AIProvider: AIUsage] = [:]
    private var generations: [AIProvider: Int] = [:]
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(subsystem: "com.kimjaeyun.codexusagemonitor", category: "Refresh")

    init(
        providers: [any AIUsageProvider] = [CodexUsageProvider(), ClaudeCodeUsageProvider()],
        settingsStore: SettingsStore? = nil,
        scheduler: (any RefreshScheduling)? = nil
    ) {
        self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
        self.settingsStore = settingsStore ?? .shared
        self.scheduler = scheduler ?? TimerRefreshScheduler()
        usageByProvider = Dictionary(uniqueKeysWithValues: AIProvider.allCases.map {
            ($0, AIUsage.unavailable(provider: $0))
        })
        diagnosticsByProvider = Dictionary(uniqueKeysWithValues: AIProvider.allCases.map {
            ($0, ProviderDiagnostics(source: $0 == .codex ? "Codex app-server" : "Unavailable"))
        })

        self.settingsStore.$revision
            .dropFirst()
            .sink { [weak self] _ in self?.settingsDidChange() }
            .store(in: &cancellables)
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        // CLI version probes can block while a provider is starting. Keep them off
        // the main actor so the menu-bar item is available immediately at launch.
        refreshDiagnostics()
        reschedule()
        if settingsStore.settings.refreshOnLaunch {
            Task { await refresh(reason: .launch) }
        }
    }

    func refresh(reason: RefreshReason = .manual, provider explicitProvider: AIProvider? = nil) async {
        let targets = explicitProvider.map { [$0] } ?? eligibleProviders(for: reason)
        for provider in targets {
            await refreshProvider(provider, reason: reason)
        }
    }

    func popoverOpened() {
        Task { await refreshForPopoverOpen() }
    }

    func refreshForPopoverOpen() async {
        guard settingsStore.settings.refreshWhenPopoverOpens else { return }
        await refresh(reason: .popover)
    }

    func handleWake() {
        guard settingsStore.settings.refreshAfterWake else { return }
        Task { await refresh(reason: .wake) }
    }

    func handleNetworkReconnect() {
        guard settingsStore.settings.refreshAfterNetworkReconnect else { return }
        Task { await refresh(reason: .network) }
    }

    func visibleProviders() -> [AIProvider] {
        settingsStore.settings.providerOrder.filter {
            let preferences = settingsStore.settings.preferences(for: $0)
            return preferences.enabled && preferences.showInPopover
        }
    }

    func visibleWindows(for provider: AIProvider) -> [UsageWindow] {
        let preferences = settingsStore.settings.preferences(for: provider)
        return (usageByProvider[provider]?.windows ?? []).filter {
            ($0.type == .fiveHour && preferences.showFiveHour)
                || ($0.type == .weekly && preferences.showWeekly)
        }
    }

    func isStale(_ provider: AIProvider, now: Date = Date()) -> Bool {
        guard let usage = usageByProvider[provider], !usage.windows.isEmpty else { return false }
        return now.timeIntervalSince(usage.lastUpdated)
            > settingsStore.settings.staleDataThreshold.clampedSeconds
    }

    func automaticRefreshTick(now: Date = Date()) async {
        let settings = settingsStore.settings
        guard settings.automaticRefresh, settings.backgroundRefresh else { return }
        if settings.pauseRefreshDuringLowPowerMode, ProcessInfo.processInfo.isLowPowerModeEnabled {
            return
        }
        if settings.pauseAutomaticRefreshOnBattery, PowerSourceMonitor.isOnBattery {
            return
        }
        let targets = eligibleProviders(for: .automatic).filter { provider in
            let interval = settings.refreshInterval(for: provider)
            guard let lastAttempt = lastAttemptByProvider[provider] else { return true }
            return now.timeIntervalSince(lastAttempt) >= interval
        }
        for provider in targets {
            await refreshProvider(provider, reason: .automatic)
        }
    }

    func reschedule() {
        scheduler.invalidate()
        let settings = settingsStore.settings
        guard settings.automaticRefresh, settings.backgroundRefresh else {
            scheduledInterval = nil
            return
        }
        let intervals = AIProvider.allCases.compactMap { provider -> TimeInterval? in
            let preferences = settings.preferences(for: provider)
            guard preferences.enabled, preferences.includeInAutomaticRefresh else { return nil }
            return settings.refreshInterval(for: provider)
        }
        guard let interval = intervals.min() else {
            scheduledInterval = nil
            return
        }
        scheduledInterval = max(30, interval)
        scheduler.schedule(every: max(30, interval)) { [weak self] in
            await self?.automaticRefreshTick()
        }
    }

    func refreshDiagnostics() {
        Task { [weak self] in
            let diagnostics = await Task.detached(priority: .utility) {
                Self.collectDiagnostics()
            }.value
            guard let self else { return }
            self.diagnosticsByProvider = diagnostics
        }
    }

    private nonisolated static func collectDiagnostics() -> [AIProvider: ProviderDiagnostics] {
        var result = Dictionary(uniqueKeysWithValues: AIProvider.allCases.map {
            ($0, ProviderDiagnostics(source: $0 == .codex ? "Codex app-server" : "No supported background interface"))
        })

        var codex = result[.codex] ?? ProviderDiagnostics()
        if let detected = try? CodexDetector().detect() {
            codex.installed = true
            codex.version = detected.version
            codex.status = "Installed"
        }
        codex.source = "Codex app-server"
        result[.codex] = codex

        var claude = result[.claudeCode] ?? ProviderDiagnostics()
        if let executable = ClaudeCodeDetector().executableURL() {
            claude.installed = true
            claude.version = (try? ProcessRunner.run(executableURL: executable, arguments: ["--version"]))?
                .standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown"
            claude.status = "Usage interface unavailable"
        }
        claude.source = "No supported background interface"
        result[.claudeCode] = claude
        return result
    }

    private func settingsDidChange() {
        settingsStore.validateDurations()
        reschedule()
        if settingsStore.settings.refreshWhenSettingsChange
            || settingsStore.settings.refreshImmediatelyAfterSettingsChange {
            Task { await refresh(reason: .settings) }
        }
    }

    private func eligibleProviders(for reason: RefreshReason) -> [AIProvider] {
        settingsStore.settings.providerOrder.filter { provider in
            let preferences = settingsStore.settings.preferences(for: provider)
            guard preferences.enabled else { return false }
            switch reason {
            case .manual: return preferences.includeInManualRefresh
            case .automatic: return preferences.includeInAutomaticRefresh
            default: return true
            }
        }
    }

    private func refreshProvider(_ providerID: AIProvider, reason: RefreshReason) async {
        guard let provider = providers[providerID] else { return }
        let generation = (generations[providerID] ?? 0) + 1
        generations[providerID] = generation
        refreshingProviders.insert(providerID)
        lastAttemptByProvider[providerID] = Date()
        updateDiagnostics(providerID) { diagnostics in
            diagnostics.lastRefresh = Date()
            diagnostics.status = "Refreshing"
        }
        defer {
            if generations[providerID] == generation { refreshingProviders.remove(providerID) }
        }

        do {
            let usage = try await fetchWithRetry(provider, providerID: providerID)
            guard generations[providerID] == generation else { return }
            evaluateNotifications(previous: previousUsageByProvider[providerID], current: usage)
            previousUsageByProvider[providerID] = usage
            usageByProvider[providerID] = usage
            errorsByProvider[providerID] = nil
            updateDiagnostics(providerID) { diagnostics in
                diagnostics.connected = true
                diagnostics.lastSuccessfulRefresh = usage.lastUpdated
                diagnostics.source = usage.source
                diagnostics.status = "Healthy"
            }
            logger.notice("Usage refresh completed for \(providerID.displayName, privacy: .public)")
        } catch {
            guard generations[providerID] == generation else { return }
            let message = (error as? LocalizedError)?.errorDescription
                ?? "\(providerID.displayName) usage is unavailable."
            errorsByProvider[providerID] = message
            if !settingsStore.settings.keepLastSuccessfulUsageOnError
                || usageByProvider[providerID]?.windows.isEmpty == true {
                usageByProvider[providerID] = .unavailable(provider: providerID)
            }
            updateDiagnostics(providerID) { diagnostics in
                diagnostics.connected = false
                diagnostics.status = message
            }
            logger.notice("Usage unavailable for \(providerID.displayName, privacy: .public)")
        }
    }

    private func fetchWithRetry(
        _ provider: any AIUsageProvider,
        providerID: AIProvider
    ) async throws -> AIUsage {
        let settings = settingsStore.settings
        let retries = settings.retryFailedRefresh ? min(5, max(0, settings.retryCount)) : 0
        var attempt = 0
        while true {
            do {
                return try await provider.fetchUsage()
            } catch {
                if error is ClaudeCodeUsageError || attempt >= retries { throw error }
                attempt += 1
                let delay = settings.retryDelay.clampedSeconds
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    private func updateDiagnostics(
        _ provider: AIProvider,
        update: (inout ProviderDiagnostics) -> Void
    ) {
        var diagnostics = diagnosticsByProvider[provider] ?? ProviderDiagnostics()
        update(&diagnostics)
        diagnosticsByProvider[provider] = diagnostics
    }

    private func evaluateNotifications(previous: AIUsage?, current: AIUsage) {
        let settings = settingsStore.settings
        guard settings.notificationsEnabled,
              settings.preferences(for: current.provider).notificationsEnabled,
              let previous else { return }
        notifyIfCrossed(
            provider: current.provider,
            type: .fiveHour,
            threshold: settings.fiveHourNotificationThreshold,
            previous: previous,
            current: current
        )
        notifyIfCrossed(
            provider: current.provider,
            type: .weekly,
            threshold: settings.weeklyNotificationThreshold,
            previous: previous,
            current: current
        )
    }

    private func notifyIfCrossed(
        provider: AIProvider,
        type: UsageWindowType,
        threshold: Int,
        previous: AIUsage,
        current: AIUsage
    ) {
        guard (1...100).contains(threshold),
              let old = previous.window(type)?.remainingPercent,
              let new = current.window(type)?.remainingPercent,
              old > Double(threshold), new <= Double(threshold) else { return }
        let content = UNMutableNotificationContent()
        content.title = String(
            format: settingsStore.localized("notification.title"),
            locale: settingsStore.settings.language.locale,
            provider.displayName
        )
        content.body = String(
            format: settingsStore.localized("notification.body"),
            locale: settingsStore.settings.language.locale,
            type == .fiveHour ? "5H" : settingsStore.localized("limit.weekly"),
            new.percentageText
        )
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "usage-\(provider.rawValue)-\(type.rawValue)-\(threshold)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
