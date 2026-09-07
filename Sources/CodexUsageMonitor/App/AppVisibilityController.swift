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
    private let shortcutManager = GlobalShortcutManager()
    private let logger = Logger(subsystem: "com.kimjaeyun.codexusagemonitor", category: "Lifecycle")

    private init() {
        SettingsKey.registerDefaults()
        globalShortcutEnabled = UserDefaults.standard.bool(forKey: SettingsKey.globalShortcutEnabled)
    }

    func configure(menuBarController: MenuBarController) {
        self.menuBarController = menuBarController
    }

    func applyStoredSettings() {
        applyAccessoryPolicy()
        setGlobalShortcutEnabled(globalShortcutEnabled)
    }

    func applyAccessoryPolicy() {
        if NSApplication.shared.activationPolicy() != .accessory {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
        activationPolicyStatus = NSApplication.shared.activationPolicy() == .accessory
            ? "Accessory — Dock hidden"
            : "Activation policy change failed"
        logger.notice("Dock policy: \(self.activationPolicyStatus, privacy: .public)")
    }

    func setGlobalShortcutEnabled(_ enabled: Bool) {
        globalShortcutEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: SettingsKey.globalShortcutEnabled)
        shortcutManager.setEnabled(enabled)
        shortcutStatus = !enabled ? "Disabled" : (shortcutManager.isRegistered
            ? "Control–Option–C"
            : "Shortcut unavailable. Use the menu bar item.")
        logger.notice("Global shortcut registered: \(self.shortcutManager.isRegistered)")
    }

    func showUsage() {
        menuBarController?.activateStatusItem()
        logger.notice("Usage popover requested")
    }

    func showSettings() {
        NSApplication.shared.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        DispatchQueue.main.async { [weak self] in
            self?.activateApplication()
        }
    }

    private func activateApplication() {
        if #available(macOS 14.0, *) {
            NSApplication.shared.activate()
        } else {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}
