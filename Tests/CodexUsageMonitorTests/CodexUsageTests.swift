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

    func testParserPreservesWeeklyWhenFiveHourWindowIsAbsent() throws {
        let data = Data(#"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":16,"windowDurationMins":10080,"resetsAt":1701000000}}}}"#.utf8)

        let usage = try CodexRateLimitParser.parse(responseData: data)

        XCTAssertNil(usage.fiveHourRemainingPercent)
        XCTAssertEqual(usage.weeklyRemainingPercent, 84)
        XCTAssertEqual(usage.availableLimits.map(\.kind), [.weekly])
        XCTAssertEqual(MenuBarSelection.automatic.presentation(in: usage).text, "Weekly 84%")
    }

    func testParserPreservesFiveHourWhenWeeklyWindowIsAbsent() throws {
        let data = Data(#"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":27,"windowDurationMins":300,"resetsAt":1700000000}}}}"#.utf8)

        let usage = try CodexRateLimitParser.parse(responseData: data)

        XCTAssertEqual(usage.fiveHourRemainingPercent, 73)
        XCTAssertNil(usage.weeklyRemainingPercent)
        XCTAssertEqual(usage.availableLimits.map(\.kind), [.fiveHour])
        XCTAssertEqual(MenuBarSelection.automatic.presentation(in: usage).text, "5H 73%")
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

    func testAllMenuBarDisplayModesUseRemainingPercentages() {
        let usage = CodexUsage(
            fiveHourRemainingPercent: 83,
            weeklyRemainingPercent: 42,
            fiveHourResetDate: nil,
            weeklyResetDate: nil,
            lastUpdated: Date(),
            source: "Test"
        )

        XCTAssertEqual(MenuBarSelection.automatic.presentation(in: usage).text, "5H 83%")
        XCTAssertEqual(MenuBarSelection.fiveHour.presentation(in: usage).text, "5H 83%")
        XCTAssertEqual(MenuBarSelection.weekly.presentation(in: usage).text, "Weekly 42%")
        XCTAssertEqual(MenuBarSelection.lowest.presentation(in: usage).text, "Low 42%")
    }

    func testDynamicLimitsIncludeBothAvailableWindows() {
        let usage = makeUsage(fiveHour: 83, weekly: 84)

        XCTAssertEqual(usage.availableLimits.map(\.kind), [.fiveHour, .weekly])
        XCTAssertEqual(usage.availableLimits.map(\.remainingPercent), [83, 84])
        XCTAssertEqual(MenuBarController.popoverHeight(visibleLimitCount: 2), 270)
    }

    func testOnlyWeeklyOmitsFiveHourAndBecomesAutomaticFallback() {
        let usage = makeUsage(fiveHour: nil, weekly: 84)

        XCTAssertEqual(usage.availableLimits.map(\.kind), [.weekly])
        XCTAssertEqual(MenuBarSelection.automatic.presentation(in: usage).text, "Weekly 84%")
        XCTAssertEqual(MenuBarSelection.fiveHour.presentation(in: usage).text, "Weekly 84%")
        XCTAssertEqual(MenuBarSelection.lowest.presentation(in: usage).text, "Weekly 84%")
        XCTAssertEqual(usage.lowestRemainingPercent, 84)
        XCTAssertEqual(MenuBarController.popoverHeight(visibleLimitCount: 1), 205)
    }

    func testOnlyFiveHourOmitsWeeklyAndSupportsFallback() {
        let usage = makeUsage(fiveHour: 73, weekly: nil)

        XCTAssertEqual(usage.availableLimits.map(\.kind), [.fiveHour])
        XCTAssertEqual(MenuBarSelection.automatic.presentation(in: usage).text, "5H 73%")
        XCTAssertEqual(MenuBarSelection.weekly.presentation(in: usage).text, "5H 73%")
        XCTAssertEqual(usage.lowestRemainingPercent, 73)
    }

    func testNoLimitsProducesNeutralMenuBarAndEmptyLayout() {
        let usage = makeUsage(fiveHour: nil, weekly: nil)

        XCTAssertTrue(usage.availableLimits.isEmpty)
        XCTAssertNil(usage.lowestRemainingPercent)
        XCTAssertEqual(MenuBarSelection.automatic.presentation(in: usage).text, "Codex --%")
        XCTAssertEqual(MenuBarController.popoverHeight(visibleLimitCount: 0), 160)
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
    func testMenuBarSelectionPersistsThroughUserDefaults() async {
        let defaults = UserDefaults.standard
        let previousSelection = defaults.object(forKey: SettingsKey.menuBarSelection)
        defer {
            if let previousSelection {
                defaults.set(previousSelection, forKey: SettingsKey.menuBarSelection)
            } else {
                defaults.removeObject(forKey: SettingsKey.menuBarSelection)
            }
        }

        defaults.set(MenuBarSelection.weekly.rawValue, forKey: SettingsKey.menuBarSelection)
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
            defaults.string(forKey: SettingsKey.menuBarSelection),
            MenuBarSelection.weekly.rawValue
        )
        XCTAssertEqual(MenuBarSelection.weekly.presentation(in: service.usage).text, "Weekly 34%")
    }

    @MainActor
    func testAppUsesAccessoryActivationPolicy() {
        let previousPolicy = NSApplication.shared.activationPolicy()
        let visibility = AppVisibilityController.shared
        defer {
            NSApplication.shared.setActivationPolicy(previousPolicy)
        }

        visibility.applyAccessoryPolicy()
        XCTAssertEqual(NSApplication.shared.activationPolicy(), .accessory)
        XCTAssertEqual(visibility.activationPolicyStatus, "Accessory — Dock hidden")
    }

    @MainActor
    func testMenuBarAppDoesNotTerminateWhenSettingsWindowCloses() {
        let delegate = AppDelegate()
        XCTAssertFalse(delegate.applicationShouldTerminateAfterLastWindowClosed(.shared))
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

    private func makeUsage(fiveHour: Double?, weekly: Double?) -> CodexUsage {
        CodexUsage(
            fiveHourRemainingPercent: fiveHour,
            weeklyRemainingPercent: weekly,
            fiveHourResetDate: fiveHour == nil ? nil : Date(timeIntervalSince1970: 1_700_000_000),
            weeklyResetDate: weekly == nil ? nil : Date(timeIntervalSince1970: 1_701_000_000),
            lastUpdated: Date(timeIntervalSince1970: 100),
            source: "Test"
        )
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
