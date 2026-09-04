import AppKit
import Foundation
import UserNotifications

@MainActor
final class UsageRefreshService: ObservableObject {
    @Published private(set) var usage = CodexUsage.unavailable()
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var detectedCodexVersion = "Detecting…"
    @Published private(set) var settingsRevision = 0

    private let provider: any CodexUsageProviding
    private let detector: CodexDetector
    private var refreshTimer: Timer?
    private var hasStarted = false
    private var previousUsage: CodexUsage?

    init(
        provider: any CodexUsageProviding = CodexAppServerUsageProvider(),
        detector: CodexDetector = CodexDetector()
    ) {
        self.provider = provider
        self.detector = detector
        UserDefaults.standard.register(defaults: [
            SettingsKey.menuBarSelection: UsageSelection.fiveHour.rawValue,
            SettingsKey.dockBadgeSelection: DockBadgeSelection.fiveHour.rawValue,
            SettingsKey.refreshInterval: RefreshInterval.fiveMinutes.rawValue,
            SettingsKey.notificationThreshold: NotificationThreshold.twenty.rawValue
        ])
    }

    var menuBarText: String {
        _ = settingsRevision
        let raw = UserDefaults.standard.string(forKey: SettingsKey.menuBarSelection)
            ?? UsageSelection.fiveHour.rawValue
        let selection = UsageSelection(rawValue: raw) ?? .fiveHour
        return selection.value(in: usage)?.percentageText ?? "--%"
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
        refreshTimer?.invalidate()
        let seconds = UserDefaults.standard.integer(forKey: SettingsKey.refreshInterval)
        let interval = RefreshInterval(rawValue: seconds) ?? .fiveMinutes
        refreshTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(interval.rawValue), repeats: true) {
            [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }
        refreshTimer?.tolerance = min(15, TimeInterval(interval.rawValue) * 0.1)
    }

    private func updateDockBadge() {
        _ = settingsRevision
        let raw = UserDefaults.standard.string(forKey: SettingsKey.dockBadgeSelection)
            ?? DockBadgeSelection.fiveHour.rawValue
        let selection = DockBadgeSelection(rawValue: raw) ?? .fiveHour
        DockBadgeManager.update(value: selection.value(in: usage), isEnabled: selection != .disabled)
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

