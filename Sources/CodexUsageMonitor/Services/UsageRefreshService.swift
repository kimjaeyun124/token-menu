import AppKit
import Foundation
import UserNotifications
import OSLog

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
    @Published private(set) var usage = CodexUsage.unavailable()
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var detectedCodexVersion = "Detecting…"
    @Published private(set) var settingsRevision = 0

    private let provider: any CodexUsageProviding
    private let detector: CodexDetector
    private let scheduler: any RefreshScheduling
    private var hasStarted = false
    private var previousUsage: CodexUsage?

    init(
        provider: any CodexUsageProviding = CodexAppServerUsageProvider(),
        detector: CodexDetector = CodexDetector(),
        scheduler: (any RefreshScheduling)? = nil
    ) {
        self.provider = provider
        self.detector = detector
        self.scheduler = scheduler ?? TimerRefreshScheduler()
        SettingsKey.registerDefaults()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        detectedCodexVersion = (try? detector.detect().version) ?? "Not installed"
        reschedule()
        Task { await refresh() }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let newUsage = try await provider.fetchUsage()
            errorMessage = nil
            evaluateNotifications(previous: previousUsage, current: newUsage)
            previousUsage = newUsage
            usage = newUsage
            updateDockBadge()
            Logger(subsystem: "com.kimjaeyun.codexusagemonitor", category: "Refresh")
                .notice("Usage refresh completed")
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Codex usage information is unavailable."
            if usage.fiveHourRemainingPercent == nil && usage.weeklyRemainingPercent == nil {
                usage = .unavailable(source: "Codex app-server")
            }
            updateDockBadge()
        }
    }

    func settingsDidChange(rescheduleTimer: Bool = false) {
        settingsRevision += 1
        updateDockBadge()
        if rescheduleTimer { reschedule() }
    }

    func reschedule() {
        scheduler.invalidate()
        let seconds = UserDefaults.standard.integer(forKey: SettingsKey.refreshInterval)
        let interval = RefreshInterval(rawValue: seconds) ?? .fiveMinutes
        scheduler.schedule(every: TimeInterval(interval.rawValue)) { [weak self] in
            await self?.refresh()
        }
    }

    private func updateDockBadge() {
        _ = settingsRevision
        let raw = UserDefaults.standard.string(forKey: SettingsKey.dockBadgeSelection)
            ?? DockBadgeSelection.fiveHour.rawValue
        let selection = DockBadgeSelection(rawValue: raw) ?? .fiveHour
        let showInDock = UserDefaults.standard.bool(forKey: SettingsKey.showInDock)
        DockBadgeManager.update(
            value: selection.value(in: usage),
            isEnabled: showInDock && selection != .disabled
        )
    }

    private func evaluateNotifications(previous: CodexUsage?, current: CodexUsage) {
        guard let previous else { return }
        let rawThreshold = UserDefaults.standard.integer(forKey: SettingsKey.notificationThreshold)
        guard let threshold = NotificationThreshold(rawValue: rawThreshold), threshold != .off else { return }
        let value = Double(threshold.rawValue)

        if crossed(value, previous: previous.fiveHourRemainingPercent, current: current.fiveHourRemainingPercent) {
            sendNotification(label: "5-hour allowance", remaining: current.fiveHourRemainingPercent)
        }
        if crossed(value, previous: previous.weeklyRemainingPercent, current: current.weeklyRemainingPercent) {
            sendNotification(label: "Weekly allowance", remaining: current.weeklyRemainingPercent)
        }
    }

    private func crossed(_ threshold: Double, previous: Double?, current: Double?) -> Bool {
        guard let previous, let current else { return false }
        return previous > threshold && current <= threshold
    }

    private func sendNotification(label: String, remaining: Double?) {
        guard let remaining else { return }
        let content = UNMutableNotificationContent()
        content.title = "Codex usage is low"
        content.body = "\(label): \(remaining.percentageText) remaining"
        content.sound = .default
        let request = UNNotificationRequest(identifier: "codex-usage-\(label)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
