import Foundation

struct DetectedCodex: Sendable {
    let executableURL: URL
    let version: String
}

enum CodexDetectionError: LocalizedError {
    case notInstalled
    case blockedByMacOS

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "Codex is not installed. Install Codex CLI or the Codex desktop app, then refresh."
        case .blockedByMacOS:
            return "macOS blocked the Codex executable because it is quarantined or in a temporary security location. Install or update Codex from the official app, then refresh."
        }
    }
}

struct CodexDetector: Sendable {
    private let overrideCandidates: [URL]?

    init(candidates: [URL]? = nil) {
        overrideCandidates = candidates
    }

    func detect() throws -> DetectedCodex {
        var foundBlockedCandidate = false
        for executableURL in candidateURLs() where isExecutable(executableURL) {
            // Never ask macOS to launch a quarantined or translocated Codex
            // binary. Doing so can trigger an XProtect warning before the
            // app-server request has a chance to report an error.
            if isBlockedByMacOS(executableURL) {
                foundBlockedCandidate = true
                continue
            }

            let version = (try? ProcessRunner.run(executableURL: executableURL, arguments: ["--version"]))?
                .standardOutput
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown"
            return DetectedCodex(executableURL: executableURL, version: version)
        }

        if foundBlockedCandidate {
            throw CodexDetectionError.blockedByMacOS
        }
        throw CodexDetectionError.notInstalled
    }

    private func candidateURLs() -> [URL] {
        if let overrideCandidates {
            return unique(overrideCandidates)
        }

        let fileManager = FileManager.default
        var candidates: [URL] = []
        let home = fileManager.homeDirectoryForCurrentUser

        // Prefer the executable bundled with the signed desktop app. The
        // standalone CLI can be installed from archives or package managers
        // and may carry a quarantine attribute that causes macOS to block it.
        candidates.append(URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"))
        candidates.append(URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex"))
        candidates.append(home.appendingPathComponent(".local/bin/codex"))
        candidates.append(URL(fileURLWithPath: "/opt/homebrew/bin/codex"))
        candidates.append(URL(fileURLWithPath: "/usr/local/bin/codex"))

        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map {
                URL(fileURLWithPath: String($0)).appendingPathComponent("codex")
            })
        }

        return unique(candidates)
    }

    private func unique(_ candidates: [URL]) -> [URL] {
        var seen = Set<String>()
        return candidates.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private func isExecutable(_ url: URL) -> Bool {
        FileManager.default.isExecutableFile(atPath: url.path)
    }

    private func isBlockedByMacOS(_ url: URL) -> Bool {
        let resolvedURL = url.resolvingSymlinksInPath()
        if resolvedURL.standardizedFileURL.path.contains("/AppTranslocation/") {
            return true
        }

        return [url, resolvedURL].contains { candidate in
            guard let values = try? candidate.resourceValues(forKeys: [.quarantinePropertiesKey]) else {
                return false
            }
            return values.quarantineProperties != nil
        }
    }
}
