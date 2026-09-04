import Foundation

struct DetectedCodex: Sendable {
    let executableURL: URL
    let version: String
}

enum CodexDetectionError: LocalizedError {
    case notInstalled

    var errorDescription: String? {
        "Codex is not installed. Install Codex CLI or the Codex desktop app, then refresh."
    }
}

struct CodexDetector: Sendable {
    func detect() throws -> DetectedCodex {
        guard let executableURL = candidateURLs().first(where: isExecutable) else {
            throw CodexDetectionError.notInstalled
        }

        let version = (try? ProcessRunner.run(executableURL: executableURL, arguments: ["--version"]))?
            .standardOutput
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown"
        return DetectedCodex(executableURL: executableURL, version: version)
    }

    private func candidateURLs() -> [URL] {
        let fileManager = FileManager.default
        var candidates: [URL] = []
        let home = fileManager.homeDirectoryForCurrentUser
        candidates.append(home.appendingPathComponent(".local/bin/codex"))
        candidates.append(URL(fileURLWithPath: "/opt/homebrew/bin/codex"))
        candidates.append(URL(fileURLWithPath: "/usr/local/bin/codex"))
        candidates.append(URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"))
        candidates.append(URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex"))

        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map {
                URL(fileURLWithPath: String($0)).appendingPathComponent("codex")
            })
        }

        var seen = Set<String>()
        return candidates.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private func isExecutable(_ url: URL) -> Bool {
        FileManager.default.isExecutableFile(atPath: url.path)
    }
}
