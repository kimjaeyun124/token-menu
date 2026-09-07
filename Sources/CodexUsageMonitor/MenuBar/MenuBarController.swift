import AppKit
import Combine
import OSLog
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(
        subsystem: "com.kimjaeyun.codexusagemonitor",
        category: "MenuBar"
    )

    init(refreshService: UsageRefreshService, visibility: AppVisibilityController) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        let rootView = UsageWindowView()
            .environmentObject(refreshService)
            .environmentObject(visibility)
        popover.contentSize = NSSize(width: 330, height: 160)
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = NSHostingController(rootView: rootView)

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
            button.toolTip = "Codex Usage"
        }

        refreshService.$usage
            .combineLatest(refreshService.$settingsRevision)
            .sink { [weak self] usage, _ in self?.updateTitle(for: usage) }
            .store(in: &cancellables)
    }

    @objc private func togglePopover() {
        logger.notice("Menu bar item activated")
        popover.isShown ? popover.performClose(nil) : showPopover()
    }

    func activateStatusItem() {
        guard !popover.isShown else { return }
        statusItem.button?.performClick(nil)
    }

    func showPopover() {
        guard let button = statusItem.button else { return }
        updateTitleForCurrentSettings()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        logger.notice("Usage popover shown")
    }

    private var latestUsage = CodexUsage.unavailable()

    private func updateTitle(for usage: CodexUsage) {
        latestUsage = usage
        popover.contentSize = NSSize(
            width: 330,
            height: Self.popoverHeight(visibleLimitCount: usage.availableLimits.count)
        )
        updateTitleForCurrentSettings()
    }

    private func updateTitleForCurrentSettings() {
        let rawSelection = UserDefaults.standard.string(forKey: SettingsKey.menuBarSelection)
        let selection = MenuBarSelection(rawValue: rawSelection ?? "") ?? .automatic
        let presentation = selection.presentation(in: latestUsage)
        statusItem.button?.title = presentation.text
        statusItem.button?.setAccessibilityLabel(
            presentation.remainingPercent == nil
                ? "Codex Usage unavailable"
                : "Codex Usage, \(presentation.text) remaining"
        )
        logger.notice("Menu bar label updated: \(presentation.text, privacy: .public)")
    }

    nonisolated static func popoverHeight(visibleLimitCount: Int) -> CGFloat {
        switch visibleLimitCount {
        case 2...: return 270
        case 1: return 205
        default: return 160
        }
    }
}
