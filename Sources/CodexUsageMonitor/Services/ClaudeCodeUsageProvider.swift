import Foundation

enum ClaudeCodeUsageError: LocalizedError, Equatable, Sendable {
    case notInstalled
    case unsupportedLocalUsage

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "Claude Code is not installed."
        case .unsupportedLocalUsage:
            return "Claude Code usage is unavailable. This version has no supported background usage interface."
        }
    }
}

struct ClaudeCodeDetector: Sendable {
    func executableURL() -> URL? {
        let fileManager = FileManager.default
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

struct ClaudeCodeUsageProvider: AIUsageProvider {
    let id = AIProvider.claudeCode
    var displayName: String { id.displayName }
    private let detector: ClaudeCodeDetector

    init(detector: ClaudeCodeDetector = ClaudeCodeDetector()) {
        self.detector = detector
    }

    func isAvailable() async -> Bool {
        // Claude Code 2.1.195 exposes rate limits only inside an active interactive
        // session (for /usage and status-line input), not to background utilities.
        false
    }

    func fetchUsage() async throws -> AIUsage {
        guard detector.executableURL() != nil else {
            throw ClaudeCodeUsageError.notInstalled
        }
        throw ClaudeCodeUsageError.unsupportedLocalUsage
    }
}
