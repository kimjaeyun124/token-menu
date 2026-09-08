import AppKit

enum ProviderIconAsset {
    static func image(for provider: AIProvider) -> NSImage? {
        let resourceName = provider == .codex ? "codex-provider" : "claude-provider"
        guard let url = resourceBundle?.url(forResource: resourceName, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        image.accessibilityDescription = provider.displayName
        return image
    }

    /// Returns a concrete-color variant for use in both the menu bar attachment
    /// and SwiftUI. The source PNGs are alpha masks, so this works even when a
    /// supplied asset is black or otherwise too dark for the current appearance.
    static func image(for provider: AIProvider, color: ProviderIconColor) -> NSImage? {
        guard let source = image(for: provider) else { return nil }
        let result = NSImage(size: source.size)
        let rect = NSRect(origin: .zero, size: source.size)
        result.lockFocus()
        color.nsColor.setFill()
        rect.fill()
        source.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1)
        result.unlockFocus()
        result.isTemplate = false
        result.accessibilityDescription = provider.displayName
        return result
    }

    private static let resourceBundle: Bundle? = {
        let bundleName = "CodexUsageMonitor_CodexUsageMonitor.bundle"
        if let resourceURL = Bundle.main.resourceURL,
           let bundle = Bundle(url: resourceURL.appendingPathComponent(bundleName)) {
            return bundle
        }
        return Bundle.module
    }()
}

private extension ProviderIconColor {
    var nsColor: NSColor {
        switch self {
        case .white: return .white
        case .black: return .black
        case .accent: return .controlAccentColor
        case .secondary: return .secondaryLabelColor
        }
    }
}
