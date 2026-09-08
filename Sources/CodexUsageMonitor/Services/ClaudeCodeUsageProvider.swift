import Foundation

enum ClaudeCodeUsageError: LocalizedError, Equatable, Sendable {
    case notInstalled
    case bridgeNotConfigured
    case malformedStatusLine
    case unsupportedPlan

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "Claude Code is not installed."
        case .bridgeNotConfigured:
            return "Connect Claude Code through its status line to share usage with Token Menu."
        case .malformedStatusLine:
            return "Claude Code returned unsupported status-line usage information."
        case .unsupportedPlan:
            return "Claude Code rate limits are available for Claude.ai Pro, Max, Team, and Enterprise plans."
        }
    }
}

struct ClaudeCodeDetector: Sendable {
    private let overrideExecutableURL: URL?

    init(overrideExecutableURL: URL? = nil) {
        self.overrideExecutableURL = overrideExecutableURL
    }

    func executableURL() -> URL? {
        let fileManager = FileManager.default
        if let overrideExecutableURL,
           fileManager.isExecutableFile(atPath: overrideExecutableURL.path) {
            return overrideExecutableURL
        }
        let home = fileManager.homeDirectoryForCurrentUser
        var candidates = [
            home.appendingPathComponent(".local/bin/claude"),
            URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            URL(fileURLWithPath: "/usr/local/bin/claude")
        ]

        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map {
                URL(fileURLWithPath: String($0)).appendingPathComponent("claude")
            })
        }

        var seen = Set<String>()
        return candidates
            .filter { seen.insert($0.standardizedFileURL.path).inserted }
            .first { fileManager.isExecutableFile(atPath: $0.path) }
    }
}

struct ClaudeRateLimitParser: Sendable {
    struct StatusLine: Decodable, Sendable {
        let rateLimits: RateLimits?
        enum CodingKeys: String, CodingKey { case rateLimits = "rate_limits" }
    }

    struct RateLimits: Decodable, Sendable {
        let fiveHour: Window?
        let sevenDay: Window?
        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
        }
    }

    struct Window: Decodable, Sendable {
        let usedPercentage: Double?
        let resetsAt: Double?
        enum CodingKeys: String, CodingKey {
            case usedPercentage = "used_percentage"
            case resetsAt = "resets_at"
        }
    }

    static func parse(data: Data, now: Date = Date()) throws -> AIUsage {
        let statusLine: StatusLine
        do {
            statusLine = try JSONDecoder().decode(StatusLine.self, from: data)
        } catch {
            throw ClaudeCodeUsageError.malformedStatusLine
        }
        guard let limits = statusLine.rateLimits else {
            throw ClaudeCodeUsageError.unsupportedPlan
        }

        var windows: [UsageWindow] = []
        if let normalized = normalizedWindow(limits.fiveHour) {
            windows.append(UsageWindow(type: .fiveHour, remainingPercent: normalized.remaining, resetDate: normalized.resetDate))
        }
        if let normalized = normalizedWindow(limits.sevenDay) {
            windows.append(UsageWindow(type: .weekly, remainingPercent: normalized.remaining, resetDate: normalized.resetDate))
        }
        guard !windows.isEmpty else { throw ClaudeCodeUsageError.unsupportedPlan }
        return AIUsage(
            provider: .claudeCode,
            windows: windows,
            lastUpdated: now,
            source: "Claude Code status line rate_limits"
        )
    }

    private struct NormalizedWindow { let remaining: Double; let resetDate: Date? }

    private static func normalizedWindow(_ window: Window?) -> NormalizedWindow? {
        guard let window, let used = window.usedPercentage,
              used.isFinite, (0...100).contains(used) else { return nil }
        let resetDate: Date?
        if let epoch = window.resetsAt, epoch.isFinite, epoch > 0 {
            resetDate = Date(timeIntervalSince1970: epoch)
        } else {
            resetDate = nil
        }
        return NormalizedWindow(remaining: 100 - used, resetDate: resetDate)
    }
}

struct ClaudeCodeUsageProvider: AIUsageProvider {
    let id = AIProvider.claudeCode
    var displayName: String { id.displayName }
    private let detector: ClaudeCodeDetector
    private let usageFileURL: URL

    init(detector: ClaudeCodeDetector = ClaudeCodeDetector(), usageFileURL: URL? = nil) {
        self.detector = detector
        self.usageFileURL = usageFileURL
            ?? ProcessInfo.processInfo.environment["TOKEN_MENU_CLAUDE_USAGE_PATH"].map(URL.init(fileURLWithPath:))
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/token-menu-statusline.json")
    }

    func isAvailable() async -> Bool {
        guard detector.executableURL() != nil,
              let data = try? Data(contentsOf: usageFileURL) else { return false }
        return (try? ClaudeRateLimitParser.parse(data: data)) != nil
    }

    func fetchUsage() async throws -> AIUsage {
        guard detector.executableURL() != nil else { throw ClaudeCodeUsageError.notInstalled }
        guard FileManager.default.fileExists(atPath: usageFileURL.path) else {
            throw ClaudeCodeUsageError.bridgeNotConfigured
        }
        let data: Data
        do {
            data = try Data(contentsOf: usageFileURL, options: [.mappedIfSafe])
        } catch {
            throw ClaudeCodeUsageError.bridgeNotConfigured
        }
        let updated = (try? usageFileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        return try ClaudeRateLimitParser.parse(data: data, now: updated)
    }
}
