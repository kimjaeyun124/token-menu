import AppKit
import ServiceManagement
import SwiftUI
import UserNotifications

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case general, menuBar, aiServices, refresh, notifications, display, advanced, diagnostics

    var id: String { rawValue }
    var localizationKey: String {
        switch self {
        case .menuBar: return "category.menu_bar"
        case .aiServices: return "category.ai_services"
        default: return "category.\(rawValue)"
        }
    }
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .menuBar: return "menubar.rectangle"
        case .aiServices: return "terminal"
        case .refresh: return "arrow.clockwise"
        case .notifications: return "bell"
        case .display: return "paintbrush"
        case .advanced: return "slider.horizontal.3"
        case .diagnostics: return "stethoscope"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var refreshService: UsageRefreshService
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var visibility: AppVisibilityController
    @State private var category = SettingsCategory.general
    @State private var launchAtLogin = LoginItemService.isEnabled
    @State private var settingsError: String?
    @State private var confirmingReset = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(l(category.localizationKey)).font(.title2.bold())
                    selectedPage
                    if let settingsError {
                        Text(settingsError).font(.caption).foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
        }
        .frame(
            minWidth: 780,
            idealWidth: 860,
            minHeight: 560,
            idealHeight: 620
        )
        .background(SettingsWindowConfigurator())
        .environment(\.locale, settingsStore.settings.language.locale)
        .onAppear {
            launchAtLogin = LoginItemService.isEnabled
            settingsStore.settings.launchAtLogin = launchAtLogin
        }
    }

    private var sidebar: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(SettingsCategory.allCases) { item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { category = item }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 15, weight: .medium))
                                .frame(width: 21)
                            Text(l(item.localizationKey))
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(category == item ? Color.primary : Color.secondary)
                        .padding(.horizontal, 13)
                        .frame(height: 40)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .background(
                            category == item
                                ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.72)
                                : .clear,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(category == item ? .isSelected : [])
                    .accessibilityLabel(l(item.localizationKey))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
        }
        .frame(width: 252)
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.72))
    }

    @ViewBuilder
    private var selectedPage: some View {
        switch category {
        case .general: generalPage
        case .menuBar: menuBarPage
        case .aiServices: providersPage
        case .refresh: refreshPage
        case .notifications: notificationsPage
        case .display: displayPage
        case .advanced: advancedPage
        case .diagnostics: diagnosticsPage
        }
    }

    private var generalPage: some View {
        Form {
            Section(l("section.startup")) {
                Picker(l("general.language"), selection: settingsStore.binding(\.language)) {
                    Text(l("language.system")).tag(AppLanguage.systemDefault)
                    Text(l("language.korean")).tag(AppLanguage.korean)
                    Text(l("language.english")).tag(AppLanguage.english)
                }
                Toggle(l("general.launch_login"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { updateLaunchAtLogin($0) }
                Toggle(l("general.open_after_launch"), isOn: settingsStore.binding(\.openPopoverAfterLaunch))
                Toggle(l("general.start_quietly"), isOn: settingsStore.binding(\.startHiddenAtLogin))
                    .disabled(!launchAtLogin)
            }
            Section(l("section.interaction")) {
                Toggle(l("general.confirm_quit"), isOn: settingsStore.binding(\.confirmBeforeQuit))
                Toggle(l("general.global_shortcut"), isOn: settingsStore.binding(\.globalShortcutEnabled))
                    .onChange(of: settingsStore.settings.globalShortcutEnabled) { _ in applyShortcut() }
                Picker(l("general.shortcut"), selection: settingsStore.binding(\.shortcutKey)) {
                    ForEach(ShortcutKey.allCases) { Text("Control–Option–\($0.rawValue)").tag($0) }
                }
                .disabled(!settingsStore.settings.globalShortcutEnabled)
                .onChange(of: settingsStore.settings.shortcutKey) { _ in applyShortcut() }
            }
        }
        .formStyle(.grouped)
    }

    private var menuBarPage: some View {
        Form {
            Section(l("section.source")) {
                Picker(l("menu_bar.providers"), selection: settingsStore.binding(\.menuBarProvider)) {
                    Text(l("option.automatic")).tag(MenuBarProviderChoice.automatic)
                    Text(l("option.codex_only")).tag(MenuBarProviderChoice.codex)
                    Text(l("option.claude_only")).tag(MenuBarProviderChoice.claudeCode)
                    Text(l("option.codex_claude")).tag(MenuBarProviderChoice.both)
                }
                Picker(l("menu_bar.limit"), selection: settingsStore.binding(\.menuBarLimit)) {
                    ForEach(MenuBarLimitChoice.allCases) { Text(localizedLimit($0)).tag($0) }
                }
            }
            Section(l("section.format")) {
                Picker(l("menu_bar.format"), selection: settingsStore.binding(\.menuBarFormat)) {
                    ForEach(MenuBarFormat.allCases) { Text($0.title).tag($0) }
                }
                Picker(l("menu_bar.identification"), selection: settingsStore.binding(\.providerIdentification)) {
                    Text(l("option.none")).tag(ProviderIdentification.none)
                    Text(l("option.icon")).tag(ProviderIdentification.icon)
                    Text(l("option.name")).tag(ProviderIdentification.name)
                    Text(l("option.icon_name")).tag(ProviderIdentification.iconAndName)
                }
                Picker(l("menu_bar.precision"), selection: settingsStore.binding(\.percentagePrecision)) {
                    Text(l("option.integer")).tag(PercentagePrecision.integer)
                    Text(l("option.one_decimal")).tag(PercentagePrecision.oneDecimal)
                }
                Picker(l("menu_bar.unavailable"), selection: settingsStore.binding(\.unavailableDisplay)) {
                    ForEach(UnavailableDisplay.allCases) { Text(localizedUnavailable($0)).tag($0) }
                }
                LabeledContent(l("menu_bar.preview"), value: previewText)
            }
        }
        .formStyle(.grouped)
    }

    private var providersPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox(l("section.provider_order")) {
                VStack(spacing: 6) {
                    ForEach(Array(settingsStore.settings.providerOrder.enumerated()), id: \.element) { index, provider in
                        HStack {
                            Text("\(index + 1). \(provider.displayName)")
                            Spacer()
                            Button { moveProvider(index, by: -1) } label: { Image(systemName: "chevron.up") }
                                .disabled(index == 0)
                            Button { moveProvider(index, by: 1) } label: { Image(systemName: "chevron.down") }
                                .disabled(index == settingsStore.settings.providerOrder.count - 1)
                        }
                    }
                }
                .padding(6)
            }
            ForEach(AIProvider.allCases) { provider in providerEditor(provider) }
        }
    }

    private func providerEditor(_ provider: AIProvider) -> some View {
        GroupBox(provider.displayName) {
                Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 8) {
                GridRow {
                    Toggle(l("option.enabled"), isOn: providerBinding(provider, \.enabled))
                    Toggle(l("services.show_popover"), isOn: providerBinding(provider, \.showInPopover))
                }
                GridRow {
                    Toggle(l("services.manual_refresh"), isOn: providerBinding(provider, \.includeInManualRefresh))
                    Toggle(l("services.automatic_refresh"), isOn: providerBinding(provider, \.includeInAutomaticRefresh))
                }
                GridRow {
                    Toggle(l("services.show_5h"), isOn: providerBinding(provider, \.showFiveHour))
                    Toggle(l("services.show_weekly"), isOn: providerBinding(provider, \.showWeekly))
                }
                GridRow {
                    Toggle(l("services.show_reset"), isOn: providerBinding(provider, \.showResetTime))
                    Toggle(l("services.show_progress"), isOn: providerBinding(provider, \.showProgressBar))
                }
            }
            .padding(8)
        }
    }

    private var displayPage: some View {
        Form {
            Section(l("section.fields")) {
                Toggle(l("usage.remaining"), isOn: settingsStore.binding(\.showRemainingPercentage))
                Toggle(l("usage.reset_time"), isOn: settingsStore.binding(\.showResetTime))
                Toggle(l("usage.progress_bars"), isOn: settingsStore.binding(\.showProgressBars))
                Toggle(l("usage.last_updated"), isOn: settingsStore.binding(\.showLastUpdatedTime))
                Toggle(l("usage.status_labels"), isOn: settingsStore.binding(\.showStatusLabels))
            }
            Section(l("section.reset_time")) {
                Picker(l("usage.reset_format"), selection: settingsStore.binding(\.resetTimeFormat)) {
                    Text(l("option.relative")).tag(ResetTimeFormat.relative)
                    Text(l("option.absolute")).tag(ResetTimeFormat.absolute)
                    Text(l("option.both")).tag(ResetTimeFormat.both)
                }
                Text(l("usage.always_remaining"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(l("display.popover")) {
                Picker(l("display.popover_size"), selection: settingsStore.binding(\.popoverSize)) {
                    Text(l("option.compact")).tag(PopoverSize.compact)
                    Text(l("option.comfortable")).tag(PopoverSize.comfortable)
                }
                Picker(l("display.popover_width"), selection: settingsStore.binding(\.popoverWidth)) {
                    ForEach(PopoverWidth.allCases) { Text(localizedWidth($0)).tag($0) }
                }
                Picker(l("display.progress_style"), selection: settingsStore.binding(\.progressBarStyle)) {
                    Text(l("option.normal")).tag(ProgressBarStyleChoice.normal)
                    Text(l("option.thin")).tag(ProgressBarStyleChoice.thin)
                    Text(l("option.hidden")).tag(ProgressBarStyleChoice.hidden)
                }
                Toggle(l("display.separators"), isOn: settingsStore.binding(\.providerSeparators))
                Toggle(l("display.icons"), isOn: settingsStore.binding(\.showProviderIcons))
                Picker(l("display.icon_color"), selection: settingsStore.binding(\.providerIconColor)) {
                    ForEach(ProviderIconColor.allCases) { color in
                        Text(l(color.localizationKey)).tag(color)
                    }
                }
                .disabled(!settingsStore.settings.showProviderIcons)
            }
            Section(l("display.thresholds")) {
                Stepper(l("display.warning", settingsStore.settings.warningThreshold), value: settingsStore.binding(\.warningThreshold), in: 1...100)
                Stepper(l("display.critical", settingsStore.settings.criticalThreshold), value: criticalThresholdBinding, in: 0...settingsStore.settings.warningThreshold)
                Text(l("display.color_note")).font(.caption).foregroundStyle(.secondary)
            }
            Section(l("section.actions")) {
                Toggle(l("display.refresh_button"), isOn: settingsStore.binding(\.showRefreshButton))
                Toggle(l("display.settings_button"), isOn: settingsStore.binding(\.showSettingsButton))
                Toggle(l("display.quit_button"), isOn: settingsStore.binding(\.showQuitButton))
            }
        }
        .formStyle(.grouped)
    }

    private var refreshPage: some View {
        Form {
            Section(l("refresh.automatic")) {
                Toggle(l("refresh.automatic"), isOn: settingsStore.binding(\.automaticRefresh))
                DurationEditor(l("refresh.interval"), duration: settingsStore.binding(\.globalRefreshInterval))
                Toggle(l("refresh.on_launch"), isOn: settingsStore.binding(\.refreshOnLaunch))
                Toggle(l("refresh.on_open"), isOn: settingsStore.binding(\.refreshWhenPopoverOpens))
                Toggle(l("refresh.after_wake"), isOn: settingsStore.binding(\.refreshAfterWake))
                Toggle(l("refresh.after_network"), isOn: settingsStore.binding(\.refreshAfterNetworkReconnect))
                Toggle(l("refresh.on_settings"), isOn: settingsStore.binding(\.refreshWhenSettingsChange))
            }
            Section(l("section.stale")) {
                DurationEditor(l("refresh.stale_threshold"), duration: settingsStore.binding(\.staleDataThreshold))
            }
            Section(l("section.provider_intervals")) {
                ForEach(AIProvider.allCases) { provider in
                    Text(provider.displayName).fontWeight(.semibold)
                    Toggle(l("refresh.use_global"), isOn: providerBinding(provider, \.useGlobalRefreshInterval))
                    if !settingsStore.preferences(for: provider).useGlobalRefreshInterval {
                        DurationEditor(l("refresh.provider_interval"), duration: providerBinding(provider, \.customRefreshInterval))
                    }
                }
            }
            Section(l("section.retry")) {
                Toggle(l("refresh.retry_failed"), isOn: settingsStore.binding(\.retryFailedRefresh))
                DurationEditor(l("refresh.retry_delay"), duration: settingsStore.binding(\.retryDelay))
                    .disabled(!settingsStore.settings.retryFailedRefresh)
                Stepper(l("refresh.retry_count", settingsStore.settings.retryCount), value: settingsStore.binding(\.retryCount), in: 0...5)
                    .disabled(!settingsStore.settings.retryFailedRefresh)
            }
        }
        .formStyle(.grouped)
    }

    private var notificationsPage: some View {
        Form {
            Section {
                Toggle(l("notifications.enabled"), isOn: settingsStore.binding(\.notificationsEnabled))
                    .onChange(of: settingsStore.settings.notificationsEnabled) { enabled in
                        if enabled {
                            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
                        }
                    }
            }
            Section(l("section.providers")) {
                Toggle(l("notifications.codex"), isOn: providerBinding(.codex, \.notificationsEnabled))
                Toggle(l("notifications.claude"), isOn: providerBinding(.claudeCode, \.notificationsEnabled))
            }
            Section(l("notifications.thresholds")) {
                Stepper(l("notifications.5h_below", settingsStore.settings.fiveHourNotificationThreshold), value: settingsStore.binding(\.fiveHourNotificationThreshold), in: 1...100)
                Stepper(l("notifications.weekly_below", settingsStore.settings.weeklyNotificationThreshold), value: settingsStore.binding(\.weeklyNotificationThreshold), in: 1...100)
                Text(l("notifications.note"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var advancedPage: some View {
        Form {
            Section(l("section.data")) {
                Toggle(l("advanced.keep_last"), isOn: settingsStore.binding(\.keepLastSuccessfulUsageOnError))
                Toggle(l("advanced.show_stale"), isOn: settingsStore.binding(\.showStaleData))
            }
            Section(l("section.background")) {
                Toggle(l("advanced.background_refresh"), isOn: settingsStore.binding(\.backgroundRefresh))
                Toggle(l("advanced.pause_battery"), isOn: settingsStore.binding(\.pauseAutomaticRefreshOnBattery))
                Toggle(l("advanced.pause_low_power"), isOn: settingsStore.binding(\.pauseRefreshDuringLowPowerMode))
                Toggle(l("advanced.refresh_settings"), isOn: settingsStore.binding(\.refreshImmediatelyAfterSettingsChange))
            }
            Section(l("section.reset")) {
                Button(l("advanced.reset"), role: .destructive) { confirmingReset = true }
                    .confirmationDialog(
                        l("advanced.reset_confirm"),
                        isPresented: $confirmingReset,
                        titleVisibility: .visible
                    ) {
                        Button(l("advanced.reset_action"), role: .destructive) { resetSettings() }
                        Button(l("action.cancel"), role: .cancel) {}
                    } message: {
                        Text(l("advanced.reset_note"))
                    }
            }
        }
        .formStyle(.grouped)
    }

    private var diagnosticsPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(AIProvider.allCases) { provider in
                let diagnostics = refreshService.diagnosticsByProvider[provider] ?? ProviderDiagnostics()
                GroupBox(provider.displayName) {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 5) {
                        diagnosticRow(
                            l("diagnostics.installed"),
                            diagnostics.installed ? l("value.installed") : l("value.not_installed")
                        )
                        diagnosticRow(l("diagnostics.connection"), diagnostics.connected ? l("diagnostics.connected") : l("status.unavailable"))
                        diagnosticRow(l("diagnostics.version"), localizedVersion(diagnostics.version))
                        diagnosticRow(l("diagnostics.last_attempt"), formatted(diagnostics.lastRefresh))
                        diagnosticRow(l("diagnostics.last_success"), formatted(diagnostics.lastSuccessfulRefresh))
                        diagnosticRow(l("diagnostics.source"), localizedSource(diagnostics.source))
                        diagnosticRow(l("diagnostics.status"), localizedStatus(diagnostics.status))
                    }
                    HStack {
                        Button(l("action.refresh_provider")) {
                            Task { await refreshService.refresh(reason: .diagnostics, provider: provider) }
                        }
                        Button(l("action.test_connection")) {
                            Task { await refreshService.refresh(reason: .diagnostics, provider: provider) }
                        }
                    }
                    .padding(.top, 8)
                }
            }
            GroupBox(l("diagnostics.application")) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 5) {
                    diagnosticRow(l("diagnostics.version"), Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development")
                    diagnosticRow(l("diagnostics.build"), Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Development")
                    diagnosticRow(l("diagnostics.launch_login"), LoginItemService.isEnabled ? l("value.enabled") : l("value.disabled"))
                    diagnosticRow(l("diagnostics.automatic_status"), refreshService.scheduledInterval.map { l("diagnostics.every_seconds", Int($0)) } ?? l("value.paused"))
                }
            }
            Text(l("diagnostics.no_secrets"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func providerBinding<Value>(
        _ provider: AIProvider,
        _ keyPath: WritableKeyPath<ProviderPreferences, Value>
    ) -> Binding<Value> {
        Binding(
            get: { settingsStore.preferences(for: provider)[keyPath: keyPath] },
            set: { value in
                settingsStore.updatePreferences(for: provider) { $0[keyPath: keyPath] = value }
            }
        )
    }

    private func l(_ key: String) -> String { settingsStore.localized(key) }

    private func l(_ key: String, _ value: Int) -> String {
        String(format: l(key), locale: settingsStore.settings.language.locale, value)
    }

    private func localizedLimit(_ choice: MenuBarLimitChoice) -> String {
        switch choice {
        case .automatic: return l("option.automatic")
        case .fiveHour: return "5H"
        case .weekly: return l("limit.weekly")
        }
    }

    private func localizedUnavailable(_ value: UnavailableDisplay) -> String {
        switch value {
        case .dashes: return "--%"
        case .notAvailable: return "N/A"
        case .hidden: return l("option.hidden")
        }
    }

    private func localizedWidth(_ width: PopoverWidth) -> String {
        l("display.width.\(width.rawValue)")
    }

    private var previewText: String {
        let sample = AIUsage(
            provider: .codex,
            windows: [UsageWindow(type: .fiveHour, remainingPercent: 28, resetDate: nil)],
            lastUpdated: Date(),
            source: "Preview"
        )
        return MenuBarPresentation.resolve(usages: [.codex: sample], settings: settingsStore.settings).text
    }

    private func localizedSource(_ source: String) -> String {
        if source == "No supported background interface" { return l("diagnostics.no_background_source") }
        return source
    }

    private func localizedStatus(_ status: String) -> String {
        switch status {
        case "Healthy": return l("diagnostics.healthy")
        case "Installed": return l("diagnostics.installed")
        case "Refreshing": return l("refresh.in_progress")
        case "Usage interface unavailable": return l("status.unsupported")
        case "Not checked": return l("status.not_checked")
        default:
            if status.contains("background usage interface") { return l("status.unsupported") }
            return status
        }
    }

    private func localizedVersion(_ version: String) -> String {
        version == "Not installed" ? l("value.not_installed") : version
    }

    private var criticalThresholdBinding: Binding<Int> {
        Binding(
            get: { settingsStore.settings.criticalThreshold },
            set: { settingsStore.settings.criticalThreshold = min($0, settingsStore.settings.warningThreshold) }
        )
    }

    @ViewBuilder
    private func diagnosticRow(_ label: String, _ value: String) -> some View {
        GridRow { Text(label).foregroundStyle(.secondary); Text(value).textSelection(.enabled) }
    }

    private func formatted(_ date: Date?) -> String {
        date?.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened)
                .locale(settingsStore.settings.language.locale)
        ) ?? l("diagnostics.never")
    }

    private func moveProvider(_ index: Int, by offset: Int) {
        let destination = index + offset
        guard settingsStore.settings.providerOrder.indices.contains(destination) else { return }
        settingsStore.settings.providerOrder.swapAt(index, destination)
    }

    private func applyShortcut() {
        let settings = settingsStore.settings
        visibility.setGlobalShortcutEnabled(settings.globalShortcutEnabled, key: settings.shortcutKey)
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try LoginItemService.service.register() }
            else { try LoginItemService.service.unregister() }
            let status = LoginItemService.service.status
            launchAtLogin = status == .enabled || status == .requiresApproval
            settingsStore.settings.launchAtLogin = launchAtLogin
            settingsError = status == .requiresApproval
                ? l("general.login_approval")
                : nil
        } catch {
            launchAtLogin = LoginItemService.isEnabled
            settingsStore.settings.launchAtLogin = launchAtLogin
            settingsError = l("general.login_packaged")
        }
    }

    private func resetSettings() {
        if LoginItemService.isEnabled { try? LoginItemService.service.unregister() }
        launchAtLogin = false
        settingsStore.resetToDefaults()
        visibility.applyStoredSettings()
        settingsError = nil
    }
}

private struct DurationEditor: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    let label: String
    @Binding var duration: RefreshDuration

    init(_ label: String, duration: Binding<RefreshDuration>) {
        self.label = label
        _duration = duration
    }

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Button { duration.value = max(minimum, duration.value - 1) } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(.borderless)
            .disabled(duration.value <= minimum)
            TextField("", value: $duration.value, format: .number)
                .labelsHidden()
                .accessibilityLabel(label)
                .textFieldStyle(.roundedBorder)
                .frame(width: 52)
                .multilineTextAlignment(.center)
            Button { duration.value = min(maximum, duration.value + 1) } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .disabled(duration.value >= maximum)
            Picker(settingsStore.localized("duration.unit"), selection: $duration.unit) {
                ForEach(DurationUnit.allCases) { unit in
                    Text(settingsStore.localized("unit.\(unit.rawValue)")) .tag(unit)
                }
            }
            .labelsHidden()
            .frame(width: 100)
        }
    }

    private var minimum: Int { duration.unit == .seconds ? 30 : 1 }
    private var maximum: Int {
        switch duration.unit {
        case .seconds: return 86_400
        case .minutes: return 1_440
        case .hours: return 24
        }
    }
}

private struct SettingsWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> SettingsWindowProbe { SettingsWindowProbe() }
    func updateNSView(_ nsView: SettingsWindowProbe, context: Context) { nsView.configureWindow() }
}

private final class SettingsWindowProbe: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureWindow()
    }

    func configureWindow() {
        guard let window else { return }
        let minimum = NSSize(width: 780, height: 560)
        window.minSize = minimum
        window.contentMinSize = minimum
        window.collectionBehavior.remove(.canJoinAllSpaces)
        window.collectionBehavior.insert(.moveToActiveSpace)

        let contentSize = window.contentView?.bounds.size ?? .zero
        guard contentSize.width < minimum.width || contentSize.height < minimum.height else { return }
        window.setContentSize(NSSize(
            width: max(contentSize.width, minimum.width),
            height: max(contentSize.height, minimum.height)
        ))
    }
}

private enum LoginItemService {
    static let identifier = "com.kimjaeyun.codexusagemonitor.Launcher"
    static var service: SMAppService { SMAppService.loginItem(identifier: identifier) }
    static var isEnabled: Bool {
        let status = service.status
        return status == .enabled || status == .requiresApproval
    }
}
