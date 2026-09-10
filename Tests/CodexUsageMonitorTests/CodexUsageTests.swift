import AppKit
import XCTest
@testable import CodexUsageMonitor

final class CodexUsageTests: XCTestCase {
    func testReadsInitializeResponseIDWithoutRateLimitShape() {
        XCTAssertEqual(
            CodexRateLimitParser.responseID(in: Data(#"{"id":1,"result":{}}"#.utf8)),
            1
        )
    }

    func testCodexParserNormalizesRemainingWindows() throws {
        let data = Data(#"""
        {"id":2,"result":{"rateLimits":{"limitId":"codex",
          "primary":{"usedPercent":17,"windowDurationMins":300,"resetsAt":1700000000},
          "secondary":{"usedPercent":39,"windowDurationMins":10080,"resetsAt":1701000000}}}}
        """#.utf8)
        let usage = try CodexRateLimitParser.parse(responseData: data, now: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(usage.provider, .codex)
        XCTAssertEqual(usage.windows.map(\.type), [.fiveHour, .weekly])
        XCTAssertEqual(usage.windows.map(\.remainingPercent), [83, 61])
        XCTAssertEqual(usage.fiveHourResetDate, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(usage.weeklyResetDate, Date(timeIntervalSince1970: 1_701_000_000))
    }

    func testCodexParserSelectsCodexBucket() throws {
        let data = Data(#"""
        {"id":2,"result":{"rateLimits":{"primary":{"usedPercent":99,"windowDurationMins":300}},
          "rateLimitsByLimitId":{"other":{"limitId":"other","primary":{"usedPercent":90,"windowDurationMins":300}},
          "codex":{"limitId":"codex","primary":{"usedPercent":6,"windowDurationMins":300},
          "secondary":{"usedPercent":89,"windowDurationMins":10080}}}}}
        """#.utf8)
        let usage = try CodexRateLimitParser.parse(responseData: data)
        XCTAssertEqual(usage.fiveHourRemainingPercent, 94)
        XCTAssertEqual(usage.weeklyRemainingPercent, 11)
    }

    func testMissingAndInvalidValuesNeverBecomeZero() throws {
        let missing = try CodexRateLimitParser.parse(
            responseData: Data(#"{"id":2,"result":{"rateLimits":{}}}"#.utf8)
        )
        let invalid = try CodexRateLimitParser.parse(
            responseData: Data(#"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":-2,"windowDurationMins":300},"secondary":{"usedPercent":101,"windowDurationMins":10080}}}}"#.utf8)
        )
        XCTAssertTrue(missing.windows.isEmpty)
        XCTAssertTrue(invalid.windows.isEmpty)
        XCTAssertNil(Double.remaining(fromUsedPercent: -1))
        XCTAssertNil(Double.remaining(fromUsedPercent: 101))
        XCTAssertEqual(Double.remaining(fromUsedPercent: 100), 0)
    }

    func testOnlyExplicitSupportedWindowDurationsAreAccepted() throws {
        let usage = try CodexRateLimitParser.parse(
            responseData: Data(#"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":17},"secondary":{"usedPercent":39,"windowDurationMins":1440}}}}"#.utf8)
        )
        XCTAssertTrue(usage.windows.isEmpty)
    }

    func testMalformedResponseIsRejected() {
        XCTAssertThrowsError(try CodexRateLimitParser.parse(responseData: Data("private".utf8)))
    }

    @MainActor
    func testDefaultSettings() {
        let store = makeStore()
        let settings = store.settings
        XCTAssertFalse(settings.launchAtLogin)
        XCTAssertFalse(settings.openPopoverAfterLaunch)
        XCTAssertTrue(settings.startHiddenAtLogin)
        XCTAssertFalse(settings.confirmBeforeQuit)
        XCTAssertFalse(settings.globalShortcutEnabled)
        XCTAssertEqual(settings.menuBarProvider, .automatic)
        XCTAssertEqual(settings.menuBarLimit, .automatic)
        XCTAssertEqual(settings.menuBarFormat, .pipe)
        XCTAssertEqual(settings.language, .systemDefault)
        XCTAssertEqual(settings.providerIdentification, .icon)
        XCTAssertEqual(settings.providerIconColor, .white)
        XCTAssertEqual(settings.percentagePrecision, .oneDecimal)
        XCTAssertTrue(settings.automaticRefresh)
        XCTAssertEqual(settings.globalRefreshInterval, .fiveMinutes)
        XCTAssertFalse(settings.notificationsEnabled)
        XCTAssertEqual(settings.popoverSize, .compact)
        XCTAssertEqual(settings.resetTimeFormat, .relative)
    }

    @MainActor
    func testSettingsPersistence() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = SettingsStore(defaults: defaults)
        store.settings.menuBarFormat = .dot
        store.settings.globalRefreshInterval = RefreshDuration(value: 2, unit: .minutes)
        store.settings.claudeCode.showInPopover = false
        store.settings.language = .korean

        let restored = SettingsStore(defaults: defaults)
        XCTAssertEqual(restored.settings.menuBarFormat, .dot)
        XCTAssertEqual(restored.settings.globalRefreshInterval, RefreshDuration(value: 2, unit: .minutes))
        XCTAssertFalse(restored.settings.claudeCode.showInPopover)
        XCTAssertEqual(restored.settings.language, .korean)
    }

    @MainActor
    func testLegacyPrecisionDefaultsToOneDecimalOnUpgrade() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        var legacy = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(AppSettings()),
            options: []
        ) as! [String: Any]
        legacy["schemaVersion"] = 3
        legacy["percentagePrecision"] = PercentagePrecision.integer.rawValue
        defaults.set(try JSONSerialization.data(withJSONObject: legacy), forKey: SettingsStore.storageKey)

        let restored = SettingsStore(defaults: defaults)
        XCTAssertEqual(restored.settings.schemaVersion, 4)
        XCTAssertEqual(restored.settings.percentagePrecision, .oneDecimal)
    }

    func testDurationUnitConversions() {
        XCTAssertEqual(RefreshDuration(value: 45, unit: .seconds).rawSeconds, 45)
        XCTAssertEqual(RefreshDuration(value: 2, unit: .minutes).rawSeconds, 120)
        XCTAssertEqual(RefreshDuration(value: 6, unit: .hours).rawSeconds, 21_600)
    }

    @MainActor
    func testRefreshIntervalMinimumIsThirtySeconds() {
        let store = makeStore()
        store.settings.globalRefreshInterval = RefreshDuration(value: 5, unit: .seconds)
        XCTAssertFalse(store.settings.globalRefreshInterval.isValid)
        store.validateDurations()
        XCTAssertEqual(store.settings.globalRefreshInterval.clampedSeconds, 30)
    }

    @MainActor
    func testRefreshIntervalMaximumIsTwentyFourHours() {
        let store = makeStore()
        store.settings.globalRefreshInterval = RefreshDuration(value: 30, unit: .hours)
        store.validateDurations()
        XCTAssertEqual(store.settings.globalRefreshInterval.clampedSeconds, 86_400)
    }

    @MainActor
    func testProviderSpecificRefreshIntervals() {
        let store = makeStore()
        store.settings.globalRefreshInterval = RefreshDuration(value: 5, unit: .minutes)
        store.settings.codex.useGlobalRefreshInterval = false
        store.settings.codex.customRefreshInterval = RefreshDuration(value: 2, unit: .minutes)
        XCTAssertEqual(store.settings.refreshInterval(for: .codex), 120)
        XCTAssertEqual(store.settings.refreshInterval(for: .claudeCode), 300)
    }

    @MainActor
    func testProviderVisibilityIsIndependent() {
        let store = makeStore()
        store.settings.claudeCode.showInPopover = false
        let service = UsageRefreshService(providers: [], settingsStore: store)
        XCTAssertEqual(service.visibleProviders(), [.codex])
        XCTAssertTrue(store.settings.claudeCode.enabled)
        XCTAssertTrue(store.settings.claudeCode.includeInAutomaticRefresh)
    }

    @MainActor
    func testProviderOrderingControlsPopoverOrder() {
        let store = makeStore()
        store.settings.providerOrder = [.claudeCode, .codex]
        let service = UsageRefreshService(providers: [], settingsStore: store)
        XCTAssertEqual(service.visibleProviders(), [.claudeCode, .codex])
    }

    @MainActor
    func testDefaultMenuBarFormatIsExactPipeStyle() {
        let store = makeStore()
        let usage = makeUsage(provider: .codex, fiveHour: 28, weekly: 84)
        let value = MenuBarPresentation.resolve(usages: [.codex: usage], settings: store.settings)
        XCTAssertEqual(value.text, "5H | 28.0%")
    }

    func testPercentageFormatterUsesExplicitFractionDigitsAndRounding() {
        XCTAssertEqual(PercentageFormatter.string(for: 0, precision: .integer), "0%")
        XCTAssertEqual(PercentageFormatter.string(for: 0, precision: .oneDecimal), "0.0%")
        XCTAssertEqual(PercentageFormatter.string(for: 1, precision: .oneDecimal), "1.0%")
        XCTAssertEqual(PercentageFormatter.string(for: 68, precision: .oneDecimal), "68.0%")
        XCTAssertEqual(PercentageFormatter.string(for: 99, precision: .oneDecimal), "99.0%")
        XCTAssertEqual(PercentageFormatter.string(for: 100, precision: .oneDecimal), "100.0%")
        XCTAssertEqual(PercentageFormatter.string(for: 51.34, precision: .oneDecimal), "51.3%")
        XCTAssertEqual(PercentageFormatter.string(for: 51.36, precision: .oneDecimal), "51.4%")
        XCTAssertEqual(PercentageFormatter.string(for: 99.96, precision: .oneDecimal), "100.0%")
    }

    func testPercentageFormatterRejectsInvalidValuesAsUnavailable() {
        XCTAssertNil(PercentageFormatter.string(for: nil, precision: .oneDecimal))
        XCTAssertNil(PercentageFormatter.string(for: -.ulpOfOne, precision: .oneDecimal))
        XCTAssertNil(PercentageFormatter.string(for: 100.001, precision: .oneDecimal))
        XCTAssertNil(PercentageFormatter.string(for: .nan, precision: .oneDecimal))
        XCTAssertNil(PercentageFormatter.string(for: .infinity, precision: .oneDecimal))
    }

    @MainActor
    func testBothProvidersUseOneDecimalMenuBarFormatting() {
        let store = makeStore()
        store.settings.menuBarProvider = .both
        store.settings.percentagePrecision = .oneDecimal
        let codex = makeUsage(provider: .codex, fiveHour: 99, weekly: nil)
        let claude = makeUsage(provider: .claudeCode, fiveHour: 71.36, weekly: nil)
        XCTAssertEqual(
            MenuBarPresentation.resolve(
                usages: [.codex: codex, .claudeCode: claude],
                settings: store.settings
            ).text,
            "5H | 99.0% / 5H | 71.4%"
        )
    }

    @MainActor
    func testWeeklyFallbackWhenFiveHourIsMissing() {
        let store = makeStore()
        let usage = makeUsage(provider: .codex, fiveHour: nil, weekly: 84)
        let value = MenuBarPresentation.resolve(usages: [.codex: usage], settings: store.settings)
        XCTAssertEqual(value.text, "Weekly | 84.0%")
    }

    @MainActor
    func testExplicitMissingLimitShowsUnavailableNotZero() {
        let store = makeStore()
        store.settings.menuBarLimit = .fiveHour
        let usage = makeUsage(provider: .codex, fiveHour: nil, weekly: 84)
        let value = MenuBarPresentation.resolve(usages: [.codex: usage], settings: store.settings)
        XCTAssertEqual(value.text, "5H | --%")
        XCTAssertNil(value.remainingPercent)
    }

    @MainActor
    func testUnavailableProviderUsesAIState() {
        let store = makeStore()
        store.settings.menuBarProvider = .claudeCode
        let value = MenuBarPresentation.resolve(
            usages: [.claudeCode: .unavailable(provider: .claudeCode)],
            settings: store.settings
        )
        XCTAssertEqual(value.text, "AI | --%")
    }

    @MainActor
    func testMenuBarProviderSelectionIsIndependentFromPopoverVisibility() {
        let store = makeStore()
        store.settings.menuBarProvider = .claudeCode
        store.settings.claudeCode.showInPopover = false
        let codex = makeUsage(provider: .codex, fiveHour: 28, weekly: 84)
        let claude = makeUsage(provider: .claudeCode, fiveHour: 71, weekly: 63)
        let value = MenuBarPresentation.resolve(
            usages: [.codex: codex, .claudeCode: claude],
            settings: store.settings
        )
        XCTAssertEqual(value.text, "5H | 71.0%")
        XCTAssertEqual(UsageRefreshService(providers: [], settingsStore: store).visibleProviders(), [.codex])
    }

    @MainActor
    func testMenuBarLimitSelectionUsesWeekly() {
        let store = makeStore()
        store.settings.menuBarLimit = .weekly
        let usage = makeUsage(provider: .codex, fiveHour: 28, weekly: 84)
        XCTAssertEqual(
            MenuBarPresentation.resolve(usages: [.codex: usage], settings: store.settings).text,
            "Weekly | 84.0%"
        )
    }

    @MainActor
    func testMenuBarFormattingPrecisionAndProviderName() {
        let store = makeStore()
        store.settings.menuBarFormat = .dot
        store.settings.percentagePrecision = .oneDecimal
        store.settings.showProviderName = true
        let usage = makeUsage(provider: .codex, fiveHour: 28.44, weekly: nil)
        XCTAssertEqual(
            MenuBarPresentation.resolve(usages: [.codex: usage], settings: store.settings).text,
            "Codex · 5H · 28.4%"
        )
    }

    @MainActor
    func testBothProvidersUseCompactSeparatedMenuBarFormat() {
        let store = makeStore()
        store.settings.menuBarProvider = .both
        store.settings.providerIdentification = .icon
        let codex = makeUsage(provider: .codex, fiveHour: 28, weekly: nil)
        let claude = makeUsage(provider: .claudeCode, fiveHour: 71, weekly: nil)
        let value = MenuBarPresentation.resolve(
            usages: [.codex: codex, .claudeCode: claude],
            settings: store.settings
        )
        XCTAssertEqual(value.text, "5H | 28.0% / 5H | 71.0%")
        XCTAssertEqual(value.segments.map(\.provider), [.codex, .claudeCode])
    }

    @MainActor
    func testKoreanLocalizationUsesRequestedNaturalLabels() {
        let store = makeStore()
        store.settings.language = .korean
        let expected = [
            "category.general": "일반",
            "category.menu_bar": "메뉴바",
            "category.ai_services": "AI 서비스",
            "category.refresh": "사용량 확인",
            "category.notifications": "알림",
            "category.display": "화면 표시",
            "category.advanced": "고급 설정",
            "category.diagnostics": "상태 및 진단",
            "refresh.interval": "확인 주기",
            "action.refresh": "다시 확인",
            "services.show_popover": "사용량 창에 표시",
            "unit.seconds": "초",
            "unit.minutes": "분",
            "unit.hours": "시간"
        ]
        for (key, value) in expected {
            XCTAssertEqual(store.localized(key), value, key)
        }
        let combined = expected.keys.map(store.localized).joined(separator: " ")
        for forbidden in ["프로바이더", "메뉴 막대", "재검색", "팝오버", "스케줄러"] {
            XCTAssertFalse(combined.contains(forbidden), forbidden)
        }
    }

    @MainActor
    func testResetDayLocalizationUsesDayHourMinuteFormat() {
        let store = makeStore()
        store.settings.language = .korean
        let korean = store.localized("reset.relative_days_hours_minutes")
        store.settings.language = .english
        let english = store.localized("reset.relative_days_hours_minutes")
        XCTAssertEqual(String(format: korean, 2, 3, 4), "2일 3시간 4분 후 초기화")
        XCTAssertEqual(String(format: english, 2, 3, 4), "Resets in 2d 3h 4m")
    }

    func testProvidedProviderIconAssetsLoadFromResources() {
        XCTAssertNotNil(ProviderIconAsset.image(for: .codex))
        XCTAssertNotNil(ProviderIconAsset.image(for: .claudeCode))
    }

    @MainActor
    func testProviderIconColorPersistsAndProducesTintedImage() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = SettingsStore(defaults: defaults)
        store.settings.providerIconColor = .accent
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.settings.providerIconColor, .accent)
        XCTAssertNotNil(ProviderIconAsset.image(for: .codex, color: .white))
        XCTAssertNotNil(ProviderIconAsset.image(for: .claudeCode, color: .black))
    }

    @MainActor
    func testEnglishAndKoreanCanSwitchLive() {
        let store = makeStore()
        store.settings.language = .english
        XCTAssertEqual(store.localized("category.refresh"), "Usage Refresh")
        XCTAssertEqual(store.localized("display.icon_color"), "Icon Color")
        store.settings.language = .korean
        XCTAssertEqual(store.localized("category.refresh"), "사용량 확인")
        XCTAssertEqual(store.localized("option.icon_color_white"), "흰색")
    }

    @MainActor
    func testUnavailableCanUseNAOrHiddenIconState() {
        let store = makeStore()
        store.settings.unavailableDisplay = .notAvailable
        XCTAssertEqual(MenuBarPresentation.resolve(usages: [:], settings: store.settings).text, "AI | N/A")
        store.settings.unavailableDisplay = .hidden
        XCTAssertEqual(MenuBarPresentation.resolve(usages: [:], settings: store.settings).text, "")
    }

    @MainActor
    func testStaleStateUsesConfiguredThresholdWithoutErasingData() async {
        let store = makeStore()
        store.settings.staleDataThreshold = RefreshDuration(value: 15, unit: .minutes)
        let usage = makeUsage(provider: .codex, fiveHour: 45, weekly: nil, updated: Date(timeIntervalSince1970: 100))
        let service = UsageRefreshService(providers: [FixedProvider(usage: usage)], settingsStore: store)
        await service.refresh(provider: .codex)
        XCTAssertTrue(service.isStale(.codex, now: Date(timeIntervalSince1970: 1_001)))
        XCTAssertEqual(service.usageByProvider[.codex]?.fiveHourRemainingPercent, 45)
    }

    @MainActor
    func testRefreshOnOpenBehavior() async {
        let store = makeStore()
        let provider = CountingProvider(usage: makeUsage(provider: .codex, fiveHour: 52, weekly: nil))
        let service = UsageRefreshService(providers: [provider], settingsStore: store)
        await service.refreshForPopoverOpen()
        let firstCount = await provider.fetchCount()
        XCTAssertEqual(firstCount, 1)

        store.settings.refreshWhenPopoverOpens = false
        await service.refreshForPopoverOpen()
        let secondCount = await provider.fetchCount()
        XCTAssertEqual(secondCount, 1)
    }

    @MainActor
    func testRetryConfigurationIsBounded() {
        let store = makeStore()
        store.settings.retryFailedRefresh = true
        store.settings.retryCount = 5
        store.settings.retryDelay = RefreshDuration(value: 30, unit: .seconds)
        XCTAssertEqual(store.settings.retryCount, 5)
        XCTAssertEqual(store.settings.retryDelay.clampedSeconds, 30)
    }

    @MainActor
    func testNotificationThresholdsPersistWithinValidRange() {
        let store = makeStore()
        store.settings.notificationsEnabled = true
        store.settings.fiveHourNotificationThreshold = 10
        store.settings.weeklyNotificationThreshold = 50
        XCTAssertTrue((1...100).contains(store.settings.fiveHourNotificationThreshold))
        XCTAssertTrue((1...100).contains(store.settings.weeklyNotificationThreshold))
    }

    @MainActor
    func testResetToDefaults() {
        let store = makeStore()
        store.settings.menuBarFormat = .space
        store.settings.notificationsEnabled = true
        store.settings.providerOrder = [.claudeCode, .codex]
        store.resetToDefaults()
        XCTAssertEqual(store.settings, AppSettings())
    }

    @MainActor
    func testAutomaticSchedulerUsesShortestProviderInterval() {
        let store = makeStore()
        store.settings.codex.useGlobalRefreshInterval = false
        store.settings.codex.customRefreshInterval = RefreshDuration(value: 45, unit: .seconds)
        store.settings.claudeCode.customRefreshInterval = RefreshDuration(value: 2, unit: .minutes)
        let scheduler = ManualRefreshScheduler()
        let service = UsageRefreshService(providers: [], settingsStore: store, scheduler: scheduler)
        service.reschedule()
        XCTAssertEqual(scheduler.interval, 45)
        XCTAssertEqual(service.scheduledInterval, 45)
    }

    @MainActor
    func testProviderDisplayControlsNeverFabricateRows() async {
        let store = makeStore()
        store.settings.codex.showFiveHour = true
        store.settings.codex.showWeekly = true
        let usage = makeUsage(provider: .codex, fiveHour: nil, weekly: 84)
        let service = UsageRefreshService(providers: [FixedProvider(usage: usage)], settingsStore: store)
        await service.refresh(provider: .codex)
        XCTAssertEqual(service.visibleWindows(for: .codex).map(\.type), [.weekly])
    }

    @MainActor
    func testHidingProgressBarsReducesPopoverHeight() {
        var settings = AppSettings()
        let visible = PopoverLayoutModel.height(providerCount: 2, rowCount: 4, unavailableCount: 0, settings: settings)
        settings.progressBarStyle = .hidden
        let hidden = PopoverLayoutModel.height(providerCount: 2, rowCount: 4, unavailableCount: 0, settings: settings)
        XCTAssertLessThan(hidden, visible)
    }

    @MainActor
    func testResetTimeDisplayModesAndHiddenLayout() {
        var settings = AppSettings()
        XCTAssertEqual(ResetTimeFormat.allCases, [.relative, .absolute, .both, .hidden])

        let relativeHeight = PopoverLayoutModel.height(
            providerCount: 1,
            rowCount: 2,
            unavailableCount: 0,
            settings: settings
        )
        settings.resetTimeFormat = .both
        let bothHeight = PopoverLayoutModel.height(
            providerCount: 1,
            rowCount: 2,
            unavailableCount: 0,
            settings: settings
        )
        settings.resetTimeFormat = .hidden
        let hiddenHeight = PopoverLayoutModel.height(
            providerCount: 1,
            rowCount: 2,
            unavailableCount: 0,
            settings: settings
        )

        XCTAssertGreaterThan(bothHeight, relativeHeight)
        XCTAssertLessThan(hiddenHeight, relativeHeight)
    }

    @MainActor
    func testResetTimeLocalizationOmitsZeroUnits() {
        let store = makeStore()
        store.settings.language = .korean
        XCTAssertEqual(String(format: store.localized("reset.relative_days_hours"), 2, 3), "2일 3시간 후 초기화")
        XCTAssertEqual(String(format: store.localized("reset.relative_days_minutes"), 2, 4), "2일 4분 후 초기화")
        XCTAssertEqual(String(format: store.localized("reset.relative_hours"), 3), "3시간 후 초기화")

        store.settings.language = .english
        XCTAssertEqual(String(format: store.localized("reset.relative_days"), 2), "Resets in 2d")
        XCTAssertEqual(String(format: store.localized("reset.relative_hours_minutes"), 3, 4), "Resets in 3h 4m")
    }

    @MainActor
    func testResetTimeAbsoluteLocalizationUsesTodayTomorrowAndDateLabels() {
        let store = makeStore()
        store.settings.language = .korean
        XCTAssertEqual(String(format: store.localized("reset.absolute_today"), "오후 11:30"), "오늘 오후 11:30 초기화")
        XCTAssertEqual(String(format: store.localized("reset.absolute_tomorrow"), "오전 4:00"), "내일 오전 4:00 초기화")

        store.settings.language = .english
        XCTAssertEqual(String(format: store.localized("reset.absolute_date"), "Sep 14", "12:11 PM"), "Resets Sep 14 at 12:11 PM")
    }

    @MainActor
    func testClaudeUnavailableDoesNotBlockCodexRefresh() async {
        let store = makeStore()
        let codexUsage = makeUsage(provider: .codex, fiveHour: 61, weekly: 80)
        let service = UsageRefreshService(
            providers: [FixedProvider(usage: codexUsage), ClaudeCodeUsageProvider()],
            settingsStore: store
        )
        await service.refresh()
        XCTAssertEqual(service.usageByProvider[.codex]?.fiveHourRemainingPercent, 61)
        XCTAssertTrue(service.usageByProvider[.claudeCode]?.windows.isEmpty ?? false)
        XCTAssertNotNil(service.errorsByProvider[.claudeCode])
    }

    @MainActor
    func testAppUsesAccessoryActivationPolicy() {
        var policy = NSApplication.ActivationPolicy.regular
        var requestedPolicy: NSApplication.ActivationPolicy?
        AppVisibilityController.shared.applyAccessoryPolicy(
            currentPolicy: { policy },
            setPolicy: {
                requestedPolicy = $0
                policy = $0
                return true
            }
        )
        XCTAssertEqual(requestedPolicy, .accessory)
        XCTAssertEqual(policy, .accessory)
        XCTAssertEqual(AppVisibilityController.shared.activationPolicyStatus, "Accessory — Dock hidden")
    }

    @MainActor
    func testMenuBarAppSurvivesSettingsWindowClose() {
        XCTAssertFalse(AppDelegate().applicationShouldTerminateAfterLastWindowClosed(.shared))
    }

    func testClaudeProviderIsUnavailableWithoutStatusLineBridge() async {
        let missingURL = URL(fileURLWithPath: "/tmp/token-menu-missing-claude-statusline-(UUID().uuidString).json")
        let available = await ClaudeCodeUsageProvider(usageFileURL: missingURL).isAvailable()
        XCTAssertFalse(available)
    }

    func testClaudeStatusLineParserMapsRateLimitsToRemainingUsage() throws {
        let data = Data(#"{"rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1738425600},"seven_day":{"used_percentage":41.2,"resets_at":1738857600}}}"#.utf8)
        let usage = try ClaudeRateLimitParser.parse(data: data, now: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(usage.provider, .claudeCode)
        XCTAssertEqual(usage.fiveHourRemainingPercent!, 76.5, accuracy: 0.001)
        XCTAssertEqual(usage.weeklyRemainingPercent!, 58.8, accuracy: 0.001)
        XCTAssertEqual(usage.fiveHourResetDate, Date(timeIntervalSince1970: 1738425600))
    }

    func testClaudeStatusLineParserRejectsMissingRateLimits() {
        XCTAssertThrowsError(try ClaudeRateLimitParser.parse(data: Data(#"{"model":{"display_name":"Sonnet"}}"#.utf8))) { error in
            XCTAssertEqual(error as? ClaudeCodeUsageError, .unsupportedPlan)
        }
    }

    func testClaudeStatusLineParserOmitsInvalidWindowButKeepsValidWindow() throws {
        let data = Data(#"{"rate_limits":{"five_hour":{"used_percentage":-1,"resets_at":1738425600},"seven_day":{"used_percentage":50,"resets_at":1738857600}}}"#.utf8)
        let usage = try ClaudeRateLimitParser.parse(data: data)
        XCTAssertNil(usage.fiveHourRemainingPercent)
        XCTAssertEqual(usage.weeklyRemainingPercent!, 50, accuracy: 0.001)
    }

    func testClaudeProviderReadsConfiguredStatusLinePayload() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("token-menu-claude-(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let payloadURL = directory.appendingPathComponent("statusline.json")
        let payload = Data(#"{"rate_limits":{"five_hour":{"used_percentage":12.5,"resets_at":1738425600}}}"#.utf8)
        try payload.write(to: payloadURL)
        let detector = ClaudeCodeDetector(overrideExecutableURL: URL(fileURLWithPath: "/usr/bin/true"))
        let usage = try await ClaudeCodeUsageProvider(detector: detector, usageFileURL: payloadURL).fetchUsage()
        XCTAssertEqual(usage.fiveHourRemainingPercent!, 87.5, accuracy: 0.001)
        XCTAssertEqual(usage.source, "Claude Code status line rate_limits")
    }

    func testLiveCodexProviderWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["CODEX_LIVE_TEST"] == "1" else {
            throw XCTSkip("Set CODEX_LIVE_TEST=1 to query the installed Codex app-server.")
        }
        let usage = try await CodexUsageProvider().fetchUsage()
        XCTAssertEqual(usage.provider, .codex)
        XCTAssertFalse(usage.windows.isEmpty)
        XCTAssertTrue(usage.windows.allSatisfy { (0...100).contains($0.remainingPercent) })
    }

    @MainActor
    private func makeStore() -> SettingsStore {
        SettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    private func makeUsage(
        provider: AIProvider,
        fiveHour: Double?,
        weekly: Double?,
        updated: Date = Date(timeIntervalSince1970: 100)
    ) -> AIUsage {
        var windows: [UsageWindow] = []
        if let fiveHour { windows.append(UsageWindow(type: .fiveHour, remainingPercent: fiveHour, resetDate: nil)) }
        if let weekly { windows.append(UsageWindow(type: .weekly, remainingPercent: weekly, resetDate: nil)) }
        return AIUsage(provider: provider, windows: windows, lastUpdated: updated, source: "Test")
    }
}

private struct FixedProvider: AIUsageProvider {
    let usage: AIUsage
    var id: AIProvider { usage.provider }
    var displayName: String { id.displayName }
    func isAvailable() async -> Bool { true }
    func fetchUsage() async throws -> AIUsage { usage }
}

private actor CountingProvider: AIUsageProvider {
    nonisolated let id: AIProvider
    nonisolated var displayName: String { id.displayName }
    private let usage: AIUsage
    private var count = 0

    init(usage: AIUsage) { id = usage.provider; self.usage = usage }
    func isAvailable() async -> Bool { true }
    func fetchUsage() async throws -> AIUsage { count += 1; return usage }
    func fetchCount() -> Int { count }
}

@MainActor
private final class ManualRefreshScheduler: RefreshScheduling {
    private(set) var interval: TimeInterval?
    private var action: (@MainActor () async -> Void)?
    func schedule(every interval: TimeInterval, action: @escaping @MainActor () async -> Void) {
        self.interval = interval
        self.action = action
    }
    func invalidate() { interval = nil; action = nil }
}
