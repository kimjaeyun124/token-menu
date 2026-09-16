import Foundation
import Network
import SwiftUI

enum CodexActivityState: Equatable, Sendable {
    case working
    case waitingForApproval
    case waitingForInput
    case completed
    case error

    var localizationKey: String {
        switch self {
        case .working: return "activity.working"
        case .waitingForApproval: return "activity.waiting_approval"
        case .waitingForInput: return "activity.waiting_input"
        case .completed: return "activity.completed"
        case .error: return "activity.error"
        }
    }
}

struct CodexActivity: Equatable, Sendable, Identifiable {
    let id: String
    let title: String?
    /// ChatGPT's Codex thread/session identifier used by the `codex://` deep link.
    /// This is separate from `id` because rollout activities use a turn-based
    /// identity to deduplicate files while their ChatGPT target is session-based.
    let chatGPTThreadID: String?
    let provider: AIProvider
    let state: CodexActivityState
    let startedAt: Date?
    let updatedAt: Date

    /// Stable enough for user-selected ordering across repeated turns in the
    /// same workspace. The raw turn id is used only when no title is known.
    var orderingKey: String {
        let workspace = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(provider.rawValue):\((workspace?.isEmpty == false ? workspace : nil) ?? id)"
    }

    /// Returns the elapsed duration at the requested instant. Completed
    /// activities use their recorded completion/update time as the endpoint
    /// so their displayed duration stays fixed after completion.
    func elapsedSeconds(at now: Date) -> TimeInterval? {
        guard let startedAt else { return nil }
        let end = state == .completed ? updatedAt : now
        return max(0, end.timeIntervalSince(startedAt))
    }

    init(
        id: String,
        title: String?,
        chatGPTThreadID: String? = nil,
        provider: AIProvider = .codex,
        state: CodexActivityState,
        startedAt: Date?,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.chatGPTThreadID = chatGPTThreadID
        self.provider = provider
        self.state = state
        self.startedAt = startedAt
        self.updatedAt = updatedAt
    }
}

enum CodexActivityOrdering {
    static func ordered(_ activities: [CodexActivity], by savedKeys: [String]) -> [CodexActivity] {
        guard !activities.isEmpty else { return [] }
        var positions: [String: Int] = [:]
        for (index, key) in savedKeys.enumerated() where positions[key] == nil {
            positions[key] = index
        }
        return activities.sorted { lhs, rhs in
            let lhsPosition = positions[lhs.orderingKey] ?? savedKeys.count
            let rhsPosition = positions[rhs.orderingKey] ?? savedKeys.count
            if lhsPosition != rhsPosition { return lhsPosition < rhsPosition }
            return (lhs.startedAt ?? lhs.updatedAt) > (rhs.startedAt ?? rhs.updatedAt)
        }
    }
}

struct CodexActivitySnapshot: Equatable, Sendable {
    let activities: [CodexActivity]
    let isConnected: Bool
    let lastUpdated: Date

    static func unavailable(at date: Date = Date()) -> CodexActivitySnapshot {
        CodexActivitySnapshot(activities: [], isConnected: false, lastUpdated: date)
    }

    var primary: CodexActivity? { activities.first }
}

enum CodexActivityParser {
    private struct Envelope: Decodable {
        let result: ResultPayload?
    }

    private struct ResultPayload: Decodable {
        let data: [ThreadRecord]?
        let thread: ThreadRecord?
    }

    private struct ThreadRecord: Decodable {
        let id: String
        let name: String?
        let preview: String?
        let createdAt: Int64?
        let updatedAt: Int64
        let status: ThreadStatus
        let turns: [TurnRecord]?
    }

    private struct ThreadStatus: Decodable {
        let type: String
        let activeFlags: [String]?
    }

    private struct TurnRecord: Decodable {
        let startedAt: Int64?
        let status: String?
    }

    static func activeThreadIDs(in responseData: Data) throws -> [String] {
        let envelope = try JSONDecoder().decode(Envelope.self, from: responseData)
        return (envelope.result?.data ?? []).compactMap { thread in
            isActive(thread.status) ? thread.id : nil
        }
    }

    static func parseThreadList(responseData: Data, now: Date = Date()) throws -> [CodexActivity] {
        let envelope = try JSONDecoder().decode(Envelope.self, from: responseData)
        return (envelope.result?.data ?? []).compactMap { thread in
            guard let state = activityState(for: thread.status) else { return nil }
            return CodexActivity(
                id: thread.id,
                title: normalizedTitle(thread.name, preview: thread.preview),
                chatGPTThreadID: thread.id,
                state: state,
                startedAt: latestStartedAt(thread.turns),
                updatedAt: Date(timeIntervalSince1970: TimeInterval(thread.updatedAt))
            )
        }
        .sorted { ($0.startedAt ?? $0.updatedAt) > ($1.startedAt ?? $1.updatedAt) }
    }

    static func mergeTurn(responseData: Data, into activity: CodexActivity) throws -> CodexActivity {
        let envelope = try JSONDecoder().decode(Envelope.self, from: responseData)
        guard let thread = envelope.result?.thread else { return activity }
        return CodexActivity(
            id: activity.id,
            title: normalizedTitle(thread.name, preview: thread.preview) ?? activity.title,
            chatGPTThreadID: thread.id,
            state: activityState(for: thread.status) ?? activity.state,
            startedAt: latestStartedAt(thread.turns) ?? activity.startedAt,
            updatedAt: Date(timeIntervalSince1970: TimeInterval(thread.updatedAt))
        )
    }

    private static func isActive(_ status: ThreadStatus) -> Bool {
        status.type == "active"
    }

    private static func activityState(for status: ThreadStatus) -> CodexActivityState? {
        guard isActive(status) else { return nil }
        let flags = Set(status.activeFlags ?? [])
        if flags.contains("waitingOnApproval") { return .waitingForApproval }
        if flags.contains("waitingOnUserInput") { return .waitingForInput }
        return .working
    }

    private static func latestStartedAt(_ turns: [TurnRecord]?) -> Date? {
        turns?.compactMap { turn in
            guard let startedAt = turn.startedAt else { return nil }
            return Date(timeIntervalSince1970: TimeInterval(startedAt))
        }.max()
    }

    private static func normalizedTitle(_ name: String?, preview: String?) -> String? {
        let value = name?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? preview?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else { return nil }
        return String(value.prefix(80))
    }
}

/// Reads only lifecycle markers from local Codex rollout files. The desktop
/// client uses a stdio app-server, so its active turn is not always visible on
/// the control socket used by the CLI daemon. Prompt and tool contents are
/// intentionally ignored.
struct CodexSessionActivityScanCache: Sendable {
    fileprivate struct Entry: Sendable {
        let modifiedAt: Date
        let activity: CodexActivity?
    }

    fileprivate var entries: [String: Entry] = [:]
}

enum CodexSessionActivityScanner {
    static func scan(
        sessionsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions"),
        now: Date = Date(),
        freshness: TimeInterval = 15 * 60
    ) -> [CodexActivity] {
        var cache = CodexSessionActivityScanCache()
        return scan(
            sessionsDirectory: sessionsDirectory,
            now: now,
            freshness: freshness,
            cache: &cache
        )
    }

    static func scan(
        sessionsDirectory: URL,
        now: Date = Date(),
        freshness: TimeInterval = 15 * 60,
        cache: inout CodexSessionActivityScanCache
    ) -> [CodexActivity] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let candidates = enumerator.compactMap { item -> (URL, Date)? in
            guard let url = item as? URL, url.pathExtension == "jsonl" else { return nil }
            guard let resourceValues = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modifiedAt = resourceValues.contentModificationDate,
                  now.timeIntervalSince(modifiedAt) <= freshness else { return nil }
            return (url, modifiedAt)
        }

        // Most rollout files are historical and can be very large. Only the
        // most recently modified candidates can contain a live turn, keeping
        // the menu-bar refresh responsive even with a long session history.
        let recentCandidates = candidates
            .sorted { $0.1 > $1.1 }
            .prefix(20)

        let recentPaths = Set(recentCandidates.map { $0.0.path })
        cache.entries = cache.entries.filter { recentPaths.contains($0.key) }

        return recentCandidates
            .compactMap { url, modifiedAt in
                if let cached = cache.entries[url.path], cached.modifiedAt == modifiedAt {
                    return cached.activity
                }
                guard let data = try? readLifecycleData(of: url) else { return nil }
                let activity = parse(data: data, updatedAt: modifiedAt, now: now)
                cache.entries[url.path] = CodexSessionActivityScanCache.Entry(
                    modifiedAt: modifiedAt,
                    activity: activity
                )
                return activity
            }
            .sorted { ($0.startedAt ?? $0.updatedAt) > ($1.startedAt ?? $1.updatedAt) }
    }

    static func parse(data: Data, updatedAt: Date, now: Date = Date()) -> CodexActivity? {
        var activeTurnID: String?
        var startedAt: Date?
        var chatGPTThreadID: String?
        var completedTurnID: String?
        var completedStartedAt: Date?

        let startedMarker = Data(#""type":"task_started""#.utf8)
        let completedMarker = Data(#""type":"task_complete""#.utf8)
        let sessionMarker = Data(#""type":"session_meta""#.utf8)
        var sessionTitle: String?
        for line in data.split(separator: 0x0A) {
            // Avoid JSON decoding prompt, tool, and token events. Lifecycle
            // markers are the only records needed for activity detection.
            guard line.range(of: startedMarker) != nil
                || line.range(of: completedMarker) != nil
                || line.range(of: sessionMarker) != nil else {
                continue
            }
            guard
                let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                let payload = object["payload"] as? [String: Any]
            else { continue }
            let type = (payload["type"] as? String) ?? (object["type"] as? String)
            guard let type else { continue }

            switch type {
            case "session_meta":
                chatGPTThreadID = (payload["session_id"] as? String)
                    ?? (payload["id"] as? String)
                if let cwd = payload["cwd"] as? String {
                    sessionTitle = workspaceName(from: cwd)
                }
            case "task_started":
                activeTurnID = payload["turn_id"] as? String
                completedTurnID = nil
                completedStartedAt = nil
                if let seconds = payload["started_at"] as? NSNumber {
                    startedAt = Date(timeIntervalSince1970: seconds.doubleValue)
                } else {
                    startedAt = now
                }
            case "task_complete":
                if activeTurnID == (payload["turn_id"] as? String) {
                    completedTurnID = activeTurnID
                    completedStartedAt = startedAt
                    activeTurnID = nil
                    startedAt = nil
                }
            default:
                continue
            }
        }

        if let activeTurnID {
            return CodexActivity(
                id: "rollout:\(activeTurnID)",
                title: sessionTitle,
                chatGPTThreadID: chatGPTThreadID,
                state: .working,
                startedAt: startedAt,
                updatedAt: updatedAt
            )
        }
        guard let completedTurnID else { return nil }
        return CodexActivity(
            id: "rollout:\(completedTurnID)",
            title: sessionTitle,
            chatGPTThreadID: chatGPTThreadID,
            state: .completed,
            startedAt: completedStartedAt,
            updatedAt: updatedAt
        )
    }

    private static func workspaceName(from path: String) -> String? {
        let directory = projectDirectory(near: URL(fileURLWithPath: path))
        if let bundleName = bundleDisplayName(in: directory) {
            return bundleName
        }
        let name = directory.lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != "/" else { return nil }
        return String(name.prefix(80))
    }

    private static func projectDirectory(near directory: URL) -> URL {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: directory.appendingPathComponent(".git").path) {
            return directory
        }

        // Codex Desktop may start in a workspace container that holds the
        // actual checkout one or two levels below it. Resolve a unique nested
        // checkout so the UI can use the product name from its bundle metadata.
        let candidates = nestedGitDirectories(in: directory, depth: 2)
        return candidates.count == 1 ? candidates[0] : directory
    }

    private static func nestedGitDirectories(in directory: URL, depth: Int) -> [URL] {
        guard depth > 0,
              let children = try? FileManager.default.contentsOfDirectory(
                  at: directory,
                  includingPropertiesForKeys: [.isDirectoryKey],
                  options: [.skipsHiddenFiles]
              ) else { return [] }

        var matches: [URL] = []
        for child in children {
            guard (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                continue
            }
            if FileManager.default.fileExists(atPath: child.appendingPathComponent(".git").path) {
                matches.append(child)
            } else if depth > 1 {
                matches.append(contentsOf: nestedGitDirectories(in: child, depth: depth - 1))
            }
        }
        return matches
    }

    private static func bundleDisplayName(in projectDirectory: URL) -> String? {
        let infoURL = projectDirectory.appendingPathComponent("support/Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let values = plist as? [String: Any] else { return nil }
        let value = (values["CFBundleDisplayName"] as? String)
            ?? (values["CFBundleName"] as? String)
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
    }

    private static let maxLifecycleReadBytes = 1 * 1024 * 1024
    private static let sessionMetadataReadBytes = 64 * 1024

    private static func readLifecycleData(of url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let fileSize = try handle.seekToEnd()
        let maxReadBytes = UInt64(maxLifecycleReadBytes)
        guard fileSize > maxReadBytes else {
            try handle.seek(toOffset: 0)
            return try handle.readToEnd() ?? Data()
        }

        // A rollout can contain gigabytes of prompt/tool output. Session
        // metadata is at the beginning and the latest lifecycle markers are
        // at the end, so keep only those two bounded regions.
        let prefixLength = min(UInt64(sessionMetadataReadBytes), maxReadBytes / 2)
        let suffixLength = maxReadBytes - prefixLength
        try handle.seek(toOffset: 0)
        let prefix = try handle.read(upToCount: Int(prefixLength)) ?? Data()
        try handle.seek(toOffset: fileSize - suffixLength)
        let suffix = try handle.read(upToCount: Int(suffixLength)) ?? Data()

        var result = prefix
        result.append(0x0A)
        result.append(suffix)
        return result
    }
}

/// Detects Claude Code's foreground CLI sessions. Claude Code is a terminal
/// process rather than a LaunchServices app, so `ps` is the reliable source
/// for discovering it. No prompt or command contents are read.
enum ClaudeCodeActivityScanner {
    static func scan(
        now: Date = Date(),
        processOutput: String? = nil
    ) -> [CodexActivity] {
        let output: String
        if let processOutput {
            output = processOutput
        } else {
            output = (try? ProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/bin/ps"),
                arguments: ["-axo", "pid=,command="]
            ).standardOutput) ?? ""
        }

        return output.split(separator: "\n").compactMap { line in
            let parts = line.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count == 2,
                  let pid = Int32(parts[0]),
                  isClaudeCommand(String(parts[1]) ) else { return nil }
            return CodexActivity(
                id: "claude:\(pid)",
                title: "Claude Code",
                provider: .claudeCode,
                state: .working,
                startedAt: nil,
                updatedAt: now
            )
        }
        .sorted { $0.id < $1.id }
    }

    private static func isClaudeCommand(_ command: String) -> Bool {
        let executable = command.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? ""
        let name = URL(fileURLWithPath: executable).lastPathComponent.lowercased()
        return name == "claude" || name == "claude-code"
    }
}

@MainActor
final class CodexActivityMonitor: ObservableObject {
    @Published private(set) var snapshot = CodexActivitySnapshot.unavailable()

    private var task: Task<Void, Never>?
    private let socketPath: String
    private let sessionsDirectory: URL
    private let desktopStateURL: URL
    private var retainedActivities: [String: CodexActivity] = [:]
    private var acknowledgedActivityIDs = Set<String>()
    private var sessionScanCache = CodexSessionActivityScanCache()

    init(
        socketPath: String = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/app-server-control/app-server-control.sock").path,
        sessionsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions"),
        desktopStateURL: URL? = nil
    ) {
        self.socketPath = socketPath
        self.sessionsDirectory = sessionsDirectory
        self.desktopStateURL = desktopStateURL ?? sessionsDirectory.deletingLastPathComponent()
            .appendingPathComponent(".codex-global-state.json")
    }

    deinit {
        task?.cancel()
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            await self?.monitorLoop()
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        retainedActivities.removeAll()
        acknowledgedActivityIDs.removeAll()
        sessionScanCache = CodexSessionActivityScanCache()
        snapshot = .unavailable()
    }

    /// Removes only a completed task whose specific result page was opened.
    func acknowledge(_ activity: CodexActivity) {
        guard activity.state == .completed else { return }
        acknowledgedActivityIDs.insert(activity.id)
        retainedActivities.removeValue(forKey: activity.id)
        snapshot = CodexActivitySnapshot(
            activities: snapshot.activities.filter { $0.id != activity.id },
            isConnected: snapshot.isConnected,
            lastUpdated: snapshot.lastUpdated
        )
    }

    var primaryElapsedSeconds: TimeInterval? {
        snapshot.primary?.elapsedSeconds(at: Date())
    }

    /// Apply the same desktop read receipts to both socket and rollout polls,
    /// including retained completions that no longer appear in recent files.
    func updateSnapshot(
        with activities: [CodexActivity],
        connectionIsHealthy: Bool,
        at now: Date = Date()
    ) {
        let retained = updateRetainedActivities(
            with: activities,
            connectionIsHealthy: connectionIsHealthy,
            at: now
        )
        let visible = unreviewedActivities(retained, at: now)
        guard activitiesChanged(from: snapshot.activities, to: visible)
            || snapshot.isConnected != connectionIsHealthy else { return }
        snapshot = CodexActivitySnapshot(
            activities: visible,
            isConnected: connectionIsHealthy,
            lastUpdated: now
        )
    }

    /// Opening the popover or pressing Refresh should apply read receipts
    /// immediately, even while the slower socket fallback poll is waiting.
    func synchronizeDesktopReadState(at now: Date = Date()) {
        let visible = unreviewedActivities(snapshot.activities, at: now)
        guard visible != snapshot.activities else { return }
        snapshot = CodexActivitySnapshot(
            activities: visible,
            isConnected: snapshot.isConnected,
            lastUpdated: snapshot.lastUpdated
        )
    }

    private func unreviewedActivities(_ activities: [CodexActivity], at now: Date) -> [CodexActivity] {
        let desktopReadState = CodexDesktopReadState.load(from: desktopStateURL)
        return activities.filter { activity in
            guard desktopReadState?.hasReviewed(activity, at: now) == true else { return true }
            // Desktop read state is authoritative on every poll. Do not turn
            // it into a permanent ID dismissal: a later unread turn can reuse
            // the same app-server thread ID between our polls.
            retainedActivities.removeValue(forKey: activity.id)
            return false
        }
    }

    private func activitiesChanged(from previous: [CodexActivity], to current: [CodexActivity]) -> Bool {
        guard previous.count == current.count else { return true }
        for (old, new) in zip(previous, current) {
            guard old.id == new.id,
                  old.title == new.title,
                  old.chatGPTThreadID == new.chatGPTThreadID,
                  old.provider == new.provider,
                  old.state == new.state,
                  old.startedAt == new.startedAt else { return true }
            // Claude process discovery has no stable timestamp; its scanner
            // supplies the current poll time for an otherwise identical PID.
            if new.provider != .claudeCode, old.updatedAt != new.updatedAt { return true }
        }
        return false
    }

    private func monitorLoop() async {
        while !Task.isCancelled {
            do {
                let client = try await CodexActivityClient(socketPath: socketPath)
                let socketActivities = try await client.fetchActiveActivities()
                guard let localActivities = await scanLocalActivities() else { return }
                updateSnapshot(
                    with: merge(socketActivities, fileActivities: localActivities),
                    connectionIsHealthy: true
                )
                await client.close()
                try await Task.sleep(for: .seconds(5))
            } catch is CancellationError {
                return
            } catch {
                guard let localActivities = await scanLocalActivities() else { return }
                updateSnapshot(
                    with: merge([], fileActivities: localActivities),
                    connectionIsHealthy: false
                )
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private func scanLocalActivities() async -> [CodexActivity]? {
        let sessionsDirectory = self.sessionsDirectory
        let existingCache = sessionScanCache
        let scanTime = Date()
        let result = await Task.detached(priority: .utility) {
            var cache = existingCache
            let fileActivities = CodexSessionActivityScanner.scan(
                sessionsDirectory: sessionsDirectory,
                now: scanTime,
                cache: &cache
            )
            let claudeActivities = ClaudeCodeActivityScanner.scan(now: scanTime)
            return (fileActivities + claudeActivities, cache)
        }.value
        guard !Task.isCancelled else { return nil }
        sessionScanCache = result.1
        return result.0
    }

    private func merge(_ socketActivities: [CodexActivity], fileActivities: [CodexActivity]) -> [CodexActivity] {
        var result = socketActivities
        let existingIDs = Set(result.map(\.id))
        result.append(contentsOf: fileActivities.filter { !existingIDs.contains($0.id) })
        return result.sorted { ($0.startedAt ?? $0.updatedAt) > ($1.startedAt ?? $1.updatedAt) }
    }

    private func updateRetainedActivities(
        with incoming: [CodexActivity],
        connectionIsHealthy: Bool,
        at now: Date
    ) -> [CodexActivity] {
        // A newly active turn is a new confirmation cycle, even when the
        // app-server reuses the same thread ID.
        for activity in incoming where activity.state != .completed {
            acknowledgedActivityIDs.remove(activity.id)
        }
        let visibleIncoming = incoming.filter {
            !(acknowledgedActivityIDs.contains($0.id) && $0.state == .completed)
        }
        let incomingIDs = Set(visibleIncoming.map(\.id))
        if connectionIsHealthy {
            for previous in snapshot.activities where !incomingIDs.contains(previous.id) {
                guard previous.state != .completed else { continue }
                guard previous.provider == .codex else {
                    // Claude Code is discovered from the current process list,
                    // which has no completion marker. Its disappearance is
                    // only evidence that the process is no longer active.
                    retainedActivities.removeValue(forKey: previous.id)
                    continue
                }
                // A project can have multiple back-to-back turns. If another
                // turn in the same project is still active, suppress the old
                // row instead of falsely showing a completed task beside it.
                guard !incoming.contains(where: { incomingActivity in
                    incomingActivity.state != .completed
                        && sameWorkspace(previous, incomingActivity)
                }) else { continue }
                retainedActivities[previous.id] = CodexActivity(
                    id: previous.id,
                    title: previous.title,
                    chatGPTThreadID: previous.chatGPTThreadID,
                    provider: previous.provider,
                    state: .completed,
                    startedAt: previous.startedAt,
                    updatedAt: now
                )
            }
        } else {
            // A socket interruption is not evidence that Codex finished the
            // task. Keep the last known active row until a healthy poll can
            // confirm completion.
            for previous in snapshot.activities where !incomingIDs.contains(previous.id) {
                retainedActivities[previous.id] = previous
            }
        }

        for activity in visibleIncoming {
            if activity.state == .completed {
                retainedActivities[activity.id] = activity
            } else {
                retainedActivities.removeValue(forKey: activity.id)
                retainedActivities = retainedActivities.filter { _, retained in
                    !sameWorkspace(retained, activity)
                }
            }
        }

        let retained = retainedActivities.values.filter { retained in
            !incomingIDs.contains(retained.id)
                && !visibleIncoming.contains(where: { incomingActivity in
                    incomingActivity.state != .completed
                        && sameWorkspace(retained, incomingActivity)
                })
        }
        return (visibleIncoming + retained).sorted {
            ($0.startedAt ?? $0.updatedAt) > ($1.startedAt ?? $1.updatedAt)
        }
    }

    private func sameWorkspace(_ lhs: CodexActivity, _ rhs: CodexActivity) -> Bool {
        guard lhs.provider == rhs.provider,
              let lhsTitle = lhs.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              let rhsTitle = rhs.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !lhsTitle.isEmpty, !rhsTitle.isEmpty else { return false }
        return lhsTitle.caseInsensitiveCompare(rhsTitle) == .orderedSame
    }
}

private final class CodexActivityClient: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "com.kimjaeyun.codexusagemonitor.codex-activity")
    private var receiveBuffer = Data()
    private var nextRequestID = 1

    init(socketPath: String) async throws {
        connection = NWConnection(to: .unix(path: socketPath), using: .tcp)
        connection.start(queue: queue)
        try await waitUntilReady()
        try await performHandshake()
        _ = try await request(method: "initialize", params: [
            "clientInfo": ["name": "token-menu-activity", "version": "1.0"],
            "capabilities": [:]
        ])
    }

    func fetchActiveActivities() async throws -> [CodexActivity] {
        let response = try await request(
            method: "thread/list",
            // Include the live in-memory server state. State-DB-only reads can
            // report every thread as `notLoaded` while a turn is running.
            params: ["archived": false, "limit": 20, "useStateDbOnly": false]
        )
        var activities = try CodexActivityParser.parseThreadList(responseData: response)
        for index in activities.indices {
            let detail = try await request(
                method: "thread/read",
                params: ["threadId": activities[index].id, "includeTurns": true]
            )
            activities[index] = try CodexActivityParser.mergeTurn(
                responseData: detail,
                into: activities[index]
            )
        }
        return activities
    }

    func close() async {
        connection.cancel()
    }

    private func waitUntilReady() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = CompletionGate()
            connection.stateUpdateHandler = { state in
                guard gate.claim() else { return }
                switch state {
                case .ready:
                    self.connection.stateUpdateHandler = nil
                    continuation.resume()
                case .failed(let error):
                    self.connection.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                case .cancelled:
                    self.connection.stateUpdateHandler = nil
                    continuation.resume(throwing: CodexActivityError.connectionClosed)
                default:
                    gate.release()
                    break
                }
            }
        }
    }

    private func performHandshake() async throws {
        let key = Data((0..<16).map { _ in UInt8.random(in: 0...255) }).base64EncodedString()
        let request = "GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: \(key)\r\nSec-WebSocket-Version: 13\r\n\r\n"
        try await send(Data(request.utf8))
        let header = try await readUntil(Data("\r\n\r\n".utf8))
        guard String(decoding: header, as: UTF8.self).hasPrefix("HTTP/1.1 101") else {
            throw CodexActivityError.invalidHandshake
        }
    }

    private func request(method: String, params: [String: Any]) async throws -> Data {
        let id = nextRequestID
        nextRequestID += 1
        let object: [String: Any] = ["id": id, "method": method, "params": params]
        let data = try JSONSerialization.data(withJSONObject: object)
        try await send(webSocketFrame(payload: data, opcode: 0x1))

        while true {
            let frame = try await nextFrame()
            guard frame.opcode == 0x1 else { continue }
            guard
                let object = try JSONSerialization.jsonObject(with: frame.payload) as? [String: Any],
                let responseID = object["id"] as? NSNumber
            else { continue }
            if responseID.intValue == id {
                if let result = object["result"] {
                    return try JSONSerialization.data(withJSONObject: ["result": result])
                }
                let code = (object["error"] as? [String: Any])?["code"] as? NSNumber
                throw CodexActivityError.requestFailed(code: code?.intValue)
            }
        }
    }

    private func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            })
        }
    }

    private func receiveChunk() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
                if let error { continuation.resume(throwing: error) }
                else if isComplete && (data == nil || data?.isEmpty == true) {
                    continuation.resume(throwing: CodexActivityError.connectionClosed)
                } else {
                    continuation.resume(returning: data ?? Data())
                }
            }
        }
    }

    private func readUntil(_ delimiter: Data) async throws -> Data {
        while receiveBuffer.range(of: delimiter) == nil {
            receiveBuffer.append(try await receiveChunk())
        }
        guard let range = receiveBuffer.range(of: delimiter) else {
            throw CodexActivityError.invalidHandshake
        }
        let result = receiveBuffer.subdata(in: receiveBuffer.startIndex..<range.upperBound)
        receiveBuffer.removeSubrange(receiveBuffer.startIndex..<range.upperBound)
        return result
    }

    private func nextFrame() async throws -> WebSocketFrame {
        while true {
            if let frame = parseFrame() { return frame }
            receiveBuffer.append(try await receiveChunk())
        }
    }

    private func parseFrame() -> WebSocketFrame? {
        guard receiveBuffer.count >= 2 else { return nil }
        let first = receiveBuffer[receiveBuffer.startIndex]
        let second = receiveBuffer[receiveBuffer.startIndex + 1]
        let masked = (second & 0x80) != 0
        var length = Int(second & 0x7F)
        var headerLength = 2
        if length == 126 {
            guard receiveBuffer.count >= 4 else { return nil }
            length = Int(receiveBuffer[receiveBuffer.startIndex + 2]) << 8
                | Int(receiveBuffer[receiveBuffer.startIndex + 3])
            headerLength = 4
        } else if length == 127 {
            guard receiveBuffer.count >= 10 else { return nil }
            length = 0
            for index in 0..<8 {
                length = (length << 8) | Int(receiveBuffer[receiveBuffer.startIndex + 2 + index])
            }
            headerLength = 10
        }
        let maskLength = masked ? 4 : 0
        guard receiveBuffer.count >= headerLength + maskLength + length else { return nil }
        let payloadStart = receiveBuffer.startIndex + headerLength + maskLength
        var payload = receiveBuffer.subdata(in: payloadStart..<(payloadStart + length))
        if masked {
            let maskStart = receiveBuffer.startIndex + headerLength
            let mask = (0..<4).map { receiveBuffer[maskStart + $0] }
            for index in payload.indices { payload[index] ^= mask[index % 4] }
        }
        receiveBuffer.removeSubrange(receiveBuffer.startIndex..<(payloadStart + length))
        return WebSocketFrame(opcode: first & 0x0F, payload: payload)
    }

    private func webSocketFrame(payload: Data, opcode: UInt8) -> Data {
        let mask = (0..<4).map { _ in UInt8.random(in: 0...255) }
        let masked = Data(payload.enumerated().map { $0.element ^ mask[$0.offset % 4] })
        var frame = Data([0x80 | opcode])
        if masked.count < 126 {
            frame.append(UInt8(0x80 | masked.count))
        } else if masked.count <= UInt16.max {
            frame.append(0x80 | 126)
            frame.append(UInt8(masked.count >> 8))
            frame.append(UInt8(masked.count & 0xFF))
        } else {
            frame.append(0x80 | 127)
            for shift in stride(from: 56, through: 0, by: -8) {
                frame.append(UInt8((masked.count >> shift) & 0xFF))
            }
        }
        frame.append(contentsOf: mask)
        frame.append(masked)
        return frame
    }
}

private struct WebSocketFrame {
    let opcode: UInt8
    let payload: Data
}

private enum CodexActivityError: Error {
    case connectionClosed
    case invalidHandshake
    case requestFailed(code: Int?)
}

private final class CompletionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return false }
        completed = true
        return true
    }

    func release() {
        lock.lock()
        completed = false
        lock.unlock()
    }
}
