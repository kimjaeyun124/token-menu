import Foundation

/// Codex Desktop persists its per-thread unread list separately from task
/// lifecycle events. App activation and a successful URL launch are not read
/// receipts; this metadata also covers results opened directly inside Codex.
struct CodexDesktopReadState {
    let unreadThreadIDs: Set<String>
    let knownThreadIDs: Set<String>

    static func load(from url: URL) -> CodexDesktopReadState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return parse(data: data)
    }

    static func parse(data: Data) -> CodexDesktopReadState? {
        guard let state = try? JSONDecoder().decode(GlobalState.self, from: data) else {
            return nil
        }

        if state.hasThreadReadState {
            // Do not guess which account/host is current or fall back to a
            // migrated legacy list when the current schema is unavailable.
            guard let desktop = state.threadReadState, desktop.version == 1,
                  desktop.unreadByIdentity.count == 1,
                  let hosts = desktop.unreadByIdentity.values.first else { return nil }
            let localHosts = hosts.filter { $0.key.hasPrefix("local:") }
            guard localHosts.count == 1, let unread = localHosts.values.first else { return nil }
            return CodexDesktopReadState(unreadThreadIDs: Set(unread), knownThreadIDs: state.knownThreadIDs)
        }

        guard let unread = state.persistedAtoms?.unreadByHost?["local"] else { return nil }
        return CodexDesktopReadState(unreadThreadIDs: Set(unread), knownThreadIDs: state.knownThreadIDs)
    }

    func hasReviewed(_ activity: CodexActivity, at now: Date) -> Bool {
        guard activity.provider == .codex, activity.state == .completed,
              let threadID = activity.chatGPTThreadID,
              knownThreadIDs.contains(threadID) else { return false }
        // Completion can reach the rollout before the desktop saves unread
        // state. Allow one normal polling interval before applying absence
        // from the unread list as a read receipt.
        guard now.timeIntervalSince(activity.updatedAt) >= 5 else { return false }
        return !unreadThreadIDs.contains(threadID)
    }

    private struct GlobalState: Decodable {
        let hasThreadReadState: Bool
        let threadReadState: ThreadReadState?
        let persistedAtoms: PersistedAtoms?
        let threadProjects: [String: ThreadReference]?
        let workspaceHints: [String: ThreadReference]?
        let projectlessThreadIDs: [String]?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            hasThreadReadState = container.contains(.threadReadState)
            threadReadState = try container.decodeIfPresent(ThreadReadState.self, forKey: .threadReadState)
            persistedAtoms = hasThreadReadState ? nil
                : try container.decodeIfPresent(PersistedAtoms.self, forKey: .persistedAtoms)
            threadProjects = try container.decodeIfPresent([String: ThreadReference].self, forKey: .threadProjects)
            workspaceHints = try container.decodeIfPresent([String: ThreadReference].self, forKey: .workspaceHints)
            projectlessThreadIDs = try container.decodeIfPresent([String].self, forKey: .projectlessThreadIDs)
        }

        // A CLI-only task absent from the desktop's records has no read
        // receipt, even if it is also absent from the desktop's unread list.
        var knownThreadIDs: Set<String> {
            Set((threadProjects ?? [:]).keys)
                .union((workspaceHints ?? [:]).keys)
                .union(projectlessThreadIDs ?? [])
        }

        enum CodingKeys: String, CodingKey {
            case threadReadState = "electron-thread-read-state-v1"
            case persistedAtoms = "electron-persisted-atom-state"
            case threadProjects = "thread-project-assignments"
            case workspaceHints = "thread-workspace-root-hints"
            case projectlessThreadIDs = "projectless-thread-ids"
        }
    }

    /// Only dictionary keys identify known threads; project details and paths
    /// are not needed for read-state synchronization.
    private struct ThreadReference: Decodable {
        init(from decoder: Decoder) {}
    }

    private struct ThreadReadState: Decodable {
        let version: Int
        let unreadByIdentity: [String: [String: [String]]]
    }

    private struct PersistedAtoms: Decodable {
        let unreadByHost: [String: [String]]?

        enum CodingKeys: String, CodingKey {
            case unreadByHost = "unread-thread-ids-by-host-v1"
        }
    }
}
