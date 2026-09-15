import AppKit

/// Opens an active Codex task in the ChatGPT desktop app.
enum CodexActivityNavigator {
    private static let chatGPTBundleIdentifier = "com.openai.codex"

    /// Builds the URL understood by ChatGPT's registered `codex` URL scheme.
    /// Keeping this pure makes the deep-link contract testable without opening
    /// an external application from unit tests.
    static func threadURL(for activity: CodexActivity) -> URL? {
        guard let identifier = activity.chatGPTThreadID,
              !identifier.isEmpty,
              let escapedID = identifier.addingPercentEncoding(withAllowedCharacters: .codexThreadPathComponent)
        else { return nil }
        return URL(string: "codex://threads/\(escapedID)")
    }

    @MainActor
    @discardableResult
    static func open(_ activity: CodexActivity) -> Bool {
        if let url = threadURL(for: activity), NSWorkspace.shared.open(url) {
            NSApp.activate(ignoringOtherApps: true)
            return true
        }

        // Activities discovered from older or incomplete rollout records may
        // not include a session ID. Still take the user to ChatGPT so the
        // click remains useful instead of silently doing nothing.
        if let appURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: chatGPTBundleIdentifier
        ) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        }
        NSApp.activate(ignoringOtherApps: true)
        // Opening the app shell is intentionally not considered opening a
        // specific result page. Completed activities are acknowledged only
        // after a task deep link succeeds.
        return false
    }
}

private extension CharacterSet {
    /// A thread ID is one URL path component; `/` must not be treated as a
    /// separator if an older session record happens to contain it.
    static let codexThreadPathComponent = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
    )
}
