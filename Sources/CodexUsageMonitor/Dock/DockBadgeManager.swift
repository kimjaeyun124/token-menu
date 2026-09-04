import AppKit

@MainActor
enum DockBadgeManager {
    static func update(value: Double?, isEnabled: Bool) {
        let dockTile = NSApplication.shared.dockTile
        guard isEnabled else {
            dockTile.badgeLabel = nil
            return
        }
        dockTile.badgeLabel = value?.percentageText ?? "--%"
        dockTile.display()
    }
}
