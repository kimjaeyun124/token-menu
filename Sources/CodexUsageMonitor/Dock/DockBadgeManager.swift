import AppKit

@MainActor
enum DockBadgeManager {
    static func update(value: Double?, isEnabled: Bool) {
        let dockTile = NSApplication.shared.dockTile
        let showInDock = UserDefaults.standard.bool(forKey: SettingsKey.showInDock)
        guard isEnabled && showInDock else {
            dockTile.badgeLabel = nil
            dockTile.display()
            return
        }
        dockTile.badgeLabel = value?.percentageText ?? "--%"
        dockTile.display()
    }
}
