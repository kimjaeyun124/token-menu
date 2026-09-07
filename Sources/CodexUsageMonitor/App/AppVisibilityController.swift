import AppKit
import SwiftUI
import OSLog

@MainActor
final class AppVisibilityController: ObservableObject {
    static let shared = AppVisibilityController()

    @Published private(set) var showInDock: Bool
    @Published private(set) var globalShortcutEnabled: Bool
    @Published private(set) var activationPolicyStatus = "Not applied"
    @Published private(set) var shortcutStatus = "Disabled"

    private var windowController: NSWindowController?
    private weak var refreshService: UsageRefreshService?
    private let shortcutManager = GlobalShortcutManager()
    private let logger = Logger(subsystem: "com.kimjaeyun.codexusagemonitor", category: "Lifecycle")

    private init() {
        SettingsKey.registerDefaults()
        showInDock = UserDefaults.standard.bool(forKey: SettingsKey.showInDock)
        globalShortcutEnabled = UserDefaults.standard.bool(forKey: SettingsKey.globalShortcutEnabled)
    }

    func configure(refreshService: UsageRefreshService) {
        self.refreshService = refreshService
    }

    func applyStoredSettings() {
        setDockVisibility(showInDock, reopenWindow: false)
        setGlobalShortcutEnabled(globalShortcutEnabled)
    }

    func setDockVisibility(_ visible: Bool, reopenWindow: Bool = true) {
        showInDock = visible
        UserDefaults.standard.set(visible, forKey: SettingsKey.showInDock)

        let policy: NSApplication.ActivationPolicy = visible ? .regular : .accessory
        if NSApplication.shared.activationPolicy() != policy {
            NSApplication.shared.setActivationPolicy(policy)
        }
        activationPolicyStatus = NSApplication.shared.activationPolicy() == policy
            ? (visible ? "Regular — Dock visible" : "Accessory — Dock hidden")
            : "Activation policy change failed"
        logger.notice("Dock policy: \(self.activationPolicyStatus, privacy: .public)")

        if !visible {
            DockBadgeManager.update(value: nil, isEnabled: false)
        }

        refreshService?.settingsDidChange()
        if visible && reopenWindow {
            reopenMainWindow()
        }
    }

    func setGlobalShortcutEnabled(_ enabled: Bool) {
        globalShortcutEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: SettingsKey.globalShortcutEnabled)
        shortcutManager.setEnabled(enabled)
        shortcutStatus = !enabled ? "Disabled" : (shortcutManager.isRegistered
            ? "Control–Option–C"
            : "Shortcut unavailable. Reopen the app from Applications or Spotlight.")
        logger.notice("Global shortcut registered: \(self.shortcutManager.isRegistered)")
    }

    func reopenMainWindow() {
        guard let refreshService else { return }
        let controller = windowController ?? makeWindowController(refreshService: refreshService)
        windowController = controller

        controller.window?.deminiaturize(nil)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        activateApplication()
        logger.notice("Main window reopened; visible: \(controller.window?.isVisible == true)")
    }

    func showSettings() {
        NSApplication.shared.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        DispatchQueue.main.async { [weak self] in
            self?.activateApplication()
        }
    }

    private func makeWindowController(refreshService: UsageRefreshService) -> NSWindowController {
        let rootView = UsageWindowView()
            .environmentObject(refreshService)
            .environmentObject(self)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 410, height: 610),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Codex Usage"
        window.identifier = NSUserInterfaceItemIdentifier("CodexUsageMainWindow")
        window.contentViewController = hostingController
        window.minSize = NSSize(width: 380, height: 560)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("CodexUsageMainWindow")
        window.center()
        return NSWindowController(window: window)
    }

    private func activateApplication() {
        if #available(macOS 14.0, *) {
            NSApplication.shared.activate()
        } else {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}
