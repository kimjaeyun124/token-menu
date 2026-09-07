import AppKit
import XCTest
@testable import CodexUsageMonitor

final class CodexUsageTests: XCTestCase {
    func testReadsInitializeResponseIDWithoutRateLimitShape() {
        let data = Data(#"{"id":1,"result":{"userAgent":"Codex Desktop/0.152.1"}}"#.utf8)
        XCTAssertEqual(CodexRateLimitParser.responseID(in: data), 1)
    }

    func testConvertsConfirmedUsedPercentToRemainingPercent() throws {
        let data = Data(#"""
        {
          "id": 2,
          "result": {
            "rateLimits": {
              "limitId": "codex",
              "primary": {"usedPercent": 17, "windowDurationMins": 300, "resetsAt": 1700000000},
              "secondary": {"usedPercent": 39, "windowDurationMins": 10080, "resetsAt": 1701000000}
            },
            "rateLimitsByLimitId": null
          }
        }
        """#.utf8)

        let usage = try CodexRateLimitParser.parse(responseData: data, now: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(usage.fiveHourRemainingPercent, 83)
        XCTAssertEqual(usage.weeklyRemainingPercent, 61)
        XCTAssertEqual(usage.lowestRemainingPercent, 61)
        XCTAssertEqual(usage.fiveHourResetDate, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(usage.weeklyResetDate, Date(timeIntervalSince1970: 1_701_000_000))
    }

    func testRejectsOutOfRangeAndNonFinitePercentages() {
        XCTAssertNil(Double.remaining(fromUsedPercent: -1))
        XCTAssertNil(Double.remaining(fromUsedPercent: 101))
        XCTAssertNil(Double.remaining(fromUsedPercent: .nan))
        XCTAssertNil(Double.remaining(fromUsedPercent: .infinity))
        XCTAssertEqual(Double.remaining(fromUsedPercent: 0), 100)
        XCTAssertEqual(Double.remaining(fromUsedPercent: 100), 0)
    }

    func testInvalidWindowValueIsUnavailableRatherThanClamped() throws {
        let data = Data(#"""
        {
          "id": 2,
          "result": {
            "rateLimits": {
              "primary": {"usedPercent": -5, "windowDurationMins": 300},
              "secondary": {"usedPercent": 105, "windowDurationMins": 10080}
            }
          }
        }
        """#.utf8)

        let usage = try CodexRateLimitParser.parse(responseData: data)

        XCTAssertNil(usage.fiveHourRemainingPercent)
        XCTAssertNil(usage.weeklyRemainingPercent)
        XCTAssertNil(usage.lowestRemainingPercent)
    }

    func testSelectsCodexBucketFromMultiBucketResponse() throws {
        let data = Data(#"""
        {
          "id": 2,
          "result": {
            "rateLimits": {"primary": {"usedPercent": 99, "windowDurationMins": 300}},
            "rateLimitsByLimitId": {
              "other": {"limitId": "other", "primary": {"usedPercent": 90, "windowDurationMins": 300}},
              "codex": {
                "limitId": "codex",
                "primary": {"usedPercent": 6, "windowDurationMins": 300},
                "secondary": {"usedPercent": 89, "windowDurationMins": 10080}
              }
            }
          }
        }
        """#.utf8)

        let usage = try CodexRateLimitParser.parse(responseData: data)

        XCTAssertEqual(usage.fiveHourRemainingPercent, 94)
        XCTAssertEqual(usage.weeklyRemainingPercent, 11)
    }

    func testWindowDurationsMustBeExplicit() throws {
        let data = Data(#"""
        {
          "id": 2,
          "result": {
            "rateLimits": {
              "primary": {"usedPercent": 17},
              "secondary": {"usedPercent": 39, "windowDurationMins": 1440}
            }
          }
        }
        """#.utf8)

        let usage = try CodexRateLimitParser.parse(responseData: data)

        XCTAssertNil(usage.fiveHourRemainingPercent)
        XCTAssertNil(usage.weeklyRemainingPercent)
    }

    func testMissingRateLimitWindowsRemainUnavailable() throws {
        let data = Data(#"{"id":2,"result":{"rateLimits":{}}}"#.utf8)
        let usage = try CodexRateLimitParser.parse(responseData: data)

        XCTAssertNil(usage.fiveHourRemainingPercent)
        XCTAssertNil(usage.weeklyRemainingPercent)
        XCTAssertNil(usage.fiveHourResetDate)
        XCTAssertNil(usage.weeklyResetDate)
    }

    func testMalformedServerResponseThrowsSanitizedError() {
        let data = Data("this is not JSON and must never be logged".utf8)
        XCTAssertThrowsError(try CodexRateLimitParser.parse(responseData: data)) { error in
            XCTAssertEqual(error as? CodexUsageError, .malformedResponse)
        }
    }

    func testUsageLevelsIncludeNonColorLabels() {
        XCTAssertEqual(UsageLevel(remainingPercent: 51), .normal)
        XCTAssertEqual(UsageLevel(remainingPercent: 50), .warning)
        XCTAssertEqual(UsageLevel(remainingPercent: 21), .warning)
        XCTAssertEqual(UsageLevel(remainingPercent: 20), .critical)
        XCTAssertEqual(UsageLevel(remainingPercent: 0), .critical)
    }

    func testAllDockDisplayModesUseRemainingPercentages() {
        let usage = CodexUsage(
            fiveHourRemainingPercent: 83,
            weeklyRemainingPercent: 42,
            fiveHourResetDate: nil,
            weeklyResetDate: nil,
            lastUpdated: Date(),
            source: "Test"
        )

        XCTAssertEqual(DockBadgeSelection.fiveHour.value(in: usage), 83)
        XCTAssertEqual(DockBadgeSelection.weekly.value(in: usage), 42)
        XCTAssertEqual(DockBadgeSelection.lowest.value(in: usage), 42)
        XCTAssertNil(DockBadgeSelection.disabled.value(in: usage))
    }

    @MainActor
    func testDockBadgeUsesPercentageOrCanBeDisabled() {
        let defaults = UserDefaults.standard
        let previousShowInDock = defaults.object(forKey: SettingsKey.showInDock)
        defer {
            if let previousShowInDock {
                defaults.set(previousShowInDock, forKey: SettingsKey.showInDock)
            } else {
                defaults.removeObject(forKey: SettingsKey.showInDock)
            }
        }
        SettingsKey.registerDefaults()
        defaults.set(true, forKey: SettingsKey.showInDock)
        _ = NSApplication.shared
        DockBadgeManager.update(value: 83, isEnabled: true)
        XCTAssertEqual(NSApp.dockTile.badgeLabel, "83%")

        DockBadgeManager.update(value: nil, isEnabled: true)
        XCTAssertEqual(NSApp.dockTile.badgeLabel, "--%")

        DockBadgeManager.update(value: 83, isEnabled: false)
        XCTAssertNil(NSApp.dockTile.badgeLabel)
    }

    @MainActor
    func testManualRefreshPublishesProviderResult() async {
        let expected = CodexUsage(
            fiveHourRemainingPercent: 72,
            weeklyRemainingPercent: 48,
            fiveHourResetDate: nil,
            weeklyResetDate: nil,
            lastUpdated: Date(),
            source: "Fixture"
        )
        let service = UsageRefreshService(provider: FixedProvider(usage: expected))

        await service.refresh()

        XCTAssertEqual(service.usage, expected)
        XCTAssertNil(service.errorMessage)
    }

    @MainActor
    func testProviderFailureProducesUnavailableState() async {
        let service = UsageRefreshService(provider: FailingProvider())

        await service.refresh()

        XCTAssertNil(service.usage.fiveHourRemainingPercent)
        XCTAssertNil(service.usage.weeklyRemainingPercent)
        XCTAssertEqual(service.errorMessage, CodexUsageError.serverUnavailable.errorDescription)
        XCTAssertFalse(service.isRefreshing)
    }

    @MainActor
    func testScheduledRefreshUsesPersistedIntervalAndFetchesUsage() async {
        let defaults = UserDefaults.standard
        let previousInterval = defaults.object(forKey: SettingsKey.refreshInterval)
        defer {
            if let previousInterval {
                defaults.set(previousInterval, forKey: SettingsKey.refreshInterval)
            } else {
                defaults.removeObject(forKey: SettingsKey.refreshInterval)
            }
        }
        defaults.set(RefreshInterval.oneMinute.rawValue, forKey: SettingsKey.refreshInterval)

        let expected = CodexUsage(
            fiveHourRemainingPercent: 64,
            weeklyRemainingPercent: 37,
            fiveHourResetDate: nil,
            weeklyResetDate: nil,
            lastUpdated: Date(),
            source: "Scheduled fixture"
        )
        let scheduler = ManualRefreshScheduler()
        let service = UsageRefreshService(provider: FixedProvider(usage: expected), scheduler: scheduler)

        service.reschedule()
        XCTAssertEqual(scheduler.interval, 60)
        await scheduler.fire()

        XCTAssertEqual(service.usage, expected)
    }

    @MainActor
    func testDockSelectionPersistsThroughUserDefaults() async {
        let defaults = UserDefaults.standard
        let previousSelection = defaults.object(forKey: SettingsKey.dockBadgeSelection)
        let previousShowInDock = defaults.object(forKey: SettingsKey.showInDock)
        defer {
            if let previousSelection {
                defaults.set(previousSelection, forKey: SettingsKey.dockBadgeSelection)
            } else {
                defaults.removeObject(forKey: SettingsKey.dockBadgeSelection)
            }
            if let previousShowInDock {
                defaults.set(previousShowInDock, forKey: SettingsKey.showInDock)
            } else {
                defaults.removeObject(forKey: SettingsKey.showInDock)
            }
        }

        defaults.set(true, forKey: SettingsKey.showInDock)
        defaults.set(DockBadgeSelection.weekly.rawValue, forKey: SettingsKey.dockBadgeSelection)
        let usage = CodexUsage(
            fiveHourRemainingPercent: 75,
            weeklyRemainingPercent: 34,
            fiveHourResetDate: nil,
            weeklyResetDate: nil,
            lastUpdated: Date(),
            source: "Settings fixture"
        )
        let service = UsageRefreshService(provider: FixedProvider(usage: usage))
        await service.refresh()

        XCTAssertEqual(
            defaults.string(forKey: SettingsKey.dockBadgeSelection),
            DockBadgeSelection.weekly.rawValue
        )
        XCTAssertEqual(NSApplication.shared.dockTile.badgeLabel, "34%")
    }

    @MainActor
    func testDockVisibilitySwitchesActivationPolicyAtRuntime() {
        let defaults = UserDefaults.standard
        let previousShowInDock = defaults.object(forKey: SettingsKey.showInDock)
        let visibility = AppVisibilityController.shared
        defer {
            let restored = (previousShowInDock as? Bool) ?? true
            defaults.set(restored, forKey: SettingsKey.showInDock)
            visibility.setDockVisibility(restored, reopenWindow: false)
        }

        visibility.setDockVisibility(false, reopenWindow: false)
        XCTAssertEqual(NSApplication.shared.activationPolicy(), .accessory)
        XCTAssertNil(NSApplication.shared.dockTile.badgeLabel)
        XCTAssertEqual(visibility.activationPolicyStatus, "Accessory — Dock hidden")

        visibility.setDockVisibility(true, reopenWindow: false)
        XCTAssertEqual(NSApplication.shared.activationPolicy(), .regular)
        visibility.setDockVisibility(true, reopenWindow: false)
        XCTAssertEqual(visibility.activationPolicyStatus, "Regular — Dock visible")
    }

    @MainActor
    func testClosedMainWindowCanBeReopened() {
        let service = UsageRefreshService(provider: FixedProvider(usage: .unavailable(source: "Test")))
        let visibility = AppVisibilityController.shared
        visibility.configure(refreshService: service)
        visibility.reopenMainWindow()

        let window = NSApplication.shared.windows.first {
            $0.identifier?.rawValue == "CodexUsageMainWindow"
        }
        XCTAssertNotNil(window)
        XCTAssertTrue(window?.isVisible == true)

        window?.close()
        XCTAssertFalse(window?.isVisible == true)
        visibility.reopenMainWindow()
        XCTAssertTrue(window?.isVisible == true)
        window?.close()
    }

    @MainActor
    func testWindowClosePolicyUsesPersistedSetting() {
        let defaults = UserDefaults.standard
        let previousValue = defaults.object(forKey: SettingsKey.keepRunningWhenWindowClosed)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: SettingsKey.keepRunningWhenWindowClosed)
            } else {
                defaults.removeObject(forKey: SettingsKey.keepRunningWhenWindowClosed)
            }
        }
        let delegate = AppDelegate()

        defaults.set(true, forKey: SettingsKey.keepRunningWhenWindowClosed)
        XCTAssertFalse(delegate.applicationShouldTerminateAfterLastWindowClosed(.shared))

        defaults.set(false, forKey: SettingsKey.keepRunningWhenWindowClosed)
        XCTAssertTrue(delegate.applicationShouldTerminateAfterLastWindowClosed(.shared))
    }

    func testLiveCodexProviderWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["CODEX_LIVE_TEST"] == "1" else {
            throw XCTSkip("Set CODEX_LIVE_TEST=1 to query the installed Codex app-server.")
        }

        let usage = try await CodexAppServerUsageProvider().fetchUsage()

        XCTAssertNotNil(usage.fiveHourRemainingPercent)
        XCTAssertNotNil(usage.weeklyRemainingPercent)
        XCTAssertTrue(usage.fiveHourRemainingPercent.map { (0...100).contains($0) } ?? false)
        XCTAssertTrue(usage.weeklyRemainingPercent.map { (0...100).contains($0) } ?? false)
        XCTAssertNotNil(usage.fiveHourResetDate)
        XCTAssertNotNil(usage.weeklyResetDate)
    }
}

private struct FixedProvider: CodexUsageProviding {
    let usage: CodexUsage
    func fetchUsage() async throws -> CodexUsage { usage }
}

private struct FailingProvider: CodexUsageProviding {
    func fetchUsage() async throws -> CodexUsage {
        throw CodexUsageError.serverUnavailable
    }
}

@MainActor
private final class ManualRefreshScheduler: RefreshScheduling {
    private(set) var interval: TimeInterval?
    private var action: (@MainActor () async -> Void)?

    func schedule(every interval: TimeInterval, action: @escaping @MainActor () async -> Void) {
        self.interval = interval
        self.action = action
    }

    func invalidate() {
        interval = nil
        action = nil
    }

    func fire() async {
        await action?()
    }
}
