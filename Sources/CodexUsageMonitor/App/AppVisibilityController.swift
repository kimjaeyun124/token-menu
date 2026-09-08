import AppKit
import SwiftUI
import OSLog

@MainActor
final class AppVisibilityController: ObservableObject {
    static let shared = AppVisibilityController()

    @Published private(set) var globalShortcutEnabled: Bool
    @Published private(set) var activationPolicyStatus = "Accessory — Dock hidden"
    @Published private(set) var shortcutStatus = "Disabled"

    private weak var menuBarController: MenuBarController?
    private weak var refreshService: UsageRefreshService?
    private var settingsWindowController: NSWindowController?
    private let shortcutManager = GlobalShortcutManager()
    private let logger = Logger(subsystem: "com.kimjaeyun.codexusagemonitor", category: "Lifecycle")

    private init() {
        globalShortcutEnabled = SettingsStore.shared.settings.globalShortcutEnabled
    }

    func configure(
        menuBarController: MenuBarController,
        refreshService: UsageRefreshService
    ) {
        self.menuBarController = menuBarController
        self.refreshService = refreshService
    }

    func applyStoredSettings() {
        applyAccessoryPolicy()
        let settings = SettingsStore.shared.settings
        setGlobalShortcutEnabled(settings.globalShortcutEnabled, key: settings.shortcutKey)
    }

    func applyAccessoryPolicy() {
        applyAccessoryPolicy(
            currentPolicy: { NSApplication.shared.activationPolicy() },
            setPolicy: { NSApplication.shared.setActivationPolicy($0) }
        )
    }

    func applyAccessoryPolicy(
        currentPolicy: () -> NSApplication.ActivationPolicy,
        setPolicy: (NSApplication.ActivationPolicy) -> Bool
    ) {
        if currentPolicy() != .accessory {
            _ = setPolicy(.accessory)
        }
        activationPolicyStatus = currentPolicy() == .accessory
            ? "Accessory — Dock hidden"
            : "Activation policy change failed"
        logger.notice("Dock policy: \(self.activationPolicyStatus, privacy: .public)")
    }

    func setGlobalShortcutEnabled(_ enabled: Bool, key: ShortcutKey) {
        globalShortcutEnabled = enabled
        shortcutManager.setEnabled(enabled, key: key)
        shortcutStatus = !enabled ? "Disabled" : (shortcutManager.isRegistered
            ? "Control–Option–\(key.rawValue)"
            : "Shortcut unavailable. Use the menu bar item.")
        logger.notice("Global shortcut registered: \(self.shortcutManager.isRegistered)")
    }

    func showUsage() {
        menuBarController?.activateStatusItem()
        logger.notice("Usage popover requested")
    }

    func showSettings() {
        activateApplication()
        if settingsWindowController == nil {
            let rootView = SettingsView()
                .environmentObject(refreshService ?? UsageRefreshService())
                .environmentObject(SettingsStore.shared)
                .environmentObject(self)
            let hostingController = NSHostingController(rootView: rootView)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 860, height: 620),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = SettingsStore.shared.localized("settings.title")
            window.contentViewController = hostingController
            window.isReleasedWhenClosed = false
            settingsWindowController = NSWindowController(window: window)
        }
        guard let window = settingsWindowController?.window else { return }
        configureSettingsWindow(window)
        window.makeKeyAndOrderFront(nil)
        activateApplication()
        // Accessory apps do not become the active application automatically on
        // newer macOS releases. Ordering regardless after activation guarantees
        // the settings window is visible on the Space the user is currently on.
        window.orderFrontRegardless()
        window.makeMain()
        logger.notice("Settings window shown on the active desktop")
    }

    private func activateApplication() {
        if #available(macOS 14.0, *) {
            NSApplication.shared.activate()
        } else {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    private func configureSettingsWindow(_ window: NSWindow) {
        let minimum = NSSize(width: 780, height: 560)
        window.minSize = minimum
        window.contentMinSize = minimum
        window.collectionBehavior.remove(.canJoinAllSpaces)
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.level = .normal
        let contentSize = window.contentView?.bounds.size ?? .zero
        if contentSize.width < minimum.width || contentSize.height < minimum.height {
            window.setContentSize(NSSize(
                width: max(contentSize.width, minimum.width),
                height: max(contentSize.height, minimum.height)
            ))
        }
    }
}
