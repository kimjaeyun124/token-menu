import AppKit
import Combine
import OSLog
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let refreshService: UsageRefreshService
    private let settingsStore: SettingsStore
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(subsystem: "com.kimjaeyun.codexusagemonitor", category: "MenuBar")

    init(
        refreshService: UsageRefreshService,
        settingsStore: SettingsStore,
        visibility: AppVisibilityController
    ) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.refreshService = refreshService
        self.settingsStore = settingsStore
        super.init()

        let rootView = UsageWindowView()
            .environmentObject(refreshService)
            .environmentObject(settingsStore)
            .environmentObject(visibility)
        popover.contentSize = NSSize(width: 320, height: 260)
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = NSHostingController(rootView: rootView)

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
            button.toolTip = settingsStore.localized("app.title")
        }

        refreshService.$usageByProvider
            .combineLatest(settingsStore.$revision)
            .sink { [weak self] _, _ in self?.updatePresentation() }
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
        updatePresentation()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        refreshService.popoverOpened()
        logger.notice("Usage popover shown")
    }

    private func updatePresentation() {
        let settings = settingsStore.settings
        let presentation = refreshService.menuBarPresentation
        let providers = refreshService.visibleProviders()
        var rowCount = 0
        var unavailableCount = 0
        for provider in providers {
            let rows = refreshService.visibleWindows(for: provider)
            if rows.isEmpty || (refreshService.isStale(provider) && !settings.showStaleData) {
                unavailableCount += 1
            } else {
                rowCount += rows.count
            }
        }
        popover.contentSize = NSSize(
            width: settings.popoverWidth.points,
            height: PopoverLayoutModel.height(
                providerCount: providers.count,
                rowCount: rowCount,
                unavailableCount: unavailableCount,
                settings: settings
            )
        )

        if presentation.text.isEmpty {
            statusItem.button?.attributedTitle = NSAttributedString()
            statusItem.button?.title = ""
            statusItem.button?.image = NSImage(
                systemSymbolName: "gauge",
                accessibilityDescription: settingsStore.localized("app.title")
            )
            statusItem.button?.imagePosition = .imageOnly
        } else {
            statusItem.button?.image = nil
            statusItem.button?.imagePosition = .noImage
            statusItem.button?.attributedTitle = attributedTitle(for: presentation, settings: settings)
        }
        statusItem.button?.toolTip = settingsStore.localized("app.title")
        let hasUsage = presentation.segments.contains { $0.remainingPercent != nil }
        statusItem.button?.setAccessibilityLabel(
            hasUsage
                ? String(
                    format: settingsStore.localized("accessibility.menu_bar_remaining"),
                    locale: settings.language.locale,
                    presentation.text
                )
                : settingsStore.localized("accessibility.usage_unavailable")
        )
        let iconCount = (settings.providerIdentification == .icon
            || settings.providerIdentification == .iconAndName)
            ? presentation.segments.reduce(into: 0) { count, segment in
                if providerIcon(segment.provider, color: settings.providerIconColor) != nil { count += 1 }
            }
            : 0
        logger.notice(
            "Menu bar label updated: \(presentation.text.isEmpty ? "hidden" : presentation.text, privacy: .public); provider icons: \(iconCount); icon color: \(settings.providerIconColor.rawValue, privacy: .public)"
        )
    }

    private func attributedTitle(
        for presentation: MenuBarPresentation,
        settings: AppSettings
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        let showIcon = settings.providerIdentification == .icon
            || settings.providerIdentification == .iconAndName

        for (index, segment) in presentation.segments.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: " / ", attributes: [.font: font]))
            }
            if showIcon, let image = providerIcon(segment.provider, color: settings.providerIconColor) {
                let attachment = NSTextAttachment()
                attachment.image = image
                attachment.bounds = NSRect(x: 0, y: -2, width: 14, height: 14)
                result.append(NSAttributedString(attachment: attachment))
                result.append(NSAttributedString(string: " ", attributes: [.font: font]))
            }
            result.append(NSAttributedString(string: segment.text, attributes: [.font: font]))
        }

        if result.length == 0 {
            result.append(NSAttributedString(string: presentation.text, attributes: [.font: font]))
        }
        return result
    }

    private func providerIcon(_ provider: AIProvider, color: ProviderIconColor) -> NSImage? {
        guard let image = ProviderIconAsset.image(for: provider, color: color) else { return nil }
        image.size = NSSize(width: 14, height: 14)
        return image
    }
}
