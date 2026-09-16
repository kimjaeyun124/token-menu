import Foundation
import XCTest
@testable import CodexUsageMonitor

final class CodexDesktopReadStateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testDesktopReadStateUsesThreadIdentityInsteadOfProjectName() throws {
        let state = try XCTUnwrap(CodexDesktopReadState.parse(data: payload(unread: ["thread-b"])))
        let read = activity(id: "rollout:turn-a", threadID: "thread-a")
        let unread = activity(id: "rollout:turn-b", threadID: "thread-b")

        XCTAssertEqual(read.title, unread.title)
        XCTAssertTrue(state.hasReviewed(read, at: now))
        XCTAssertFalse(state.hasReviewed(unread, at: now))
    }

    func testLegacyLocalReadStateIsSupported() throws {
        let data = Data(#"""
        {"electron-persisted-atom-state":{"unread-thread-ids-by-host-v1":{
          "local":["thread-b"],"remote":["thread-a"]}},
         "projectless-thread-ids":["thread-a","thread-b"]}
        """#.utf8)
        let state = try XCTUnwrap(CodexDesktopReadState.parse(data: data))
        XCTAssertTrue(state.hasReviewed(activity(threadID: "thread-a"), at: now))
        XCTAssertFalse(state.hasReviewed(activity(threadID: "thread-b"), at: now))
    }

    func testMissingMalformedAndAmbiguousReadStateIsUnavailable() {
        let invalid = [
            "{",
            "{}",
            #"{"electron-thread-read-state-v1":{"version":1,"unreadByIdentity":{}}}"#,
            #"{"electron-thread-read-state-v1":{"version":1,"unreadByIdentity":{"a":{"remote:host":[]}}}}"#,
            #"{"electron-thread-read-state-v1":{"version":1,"unreadByIdentity":{"a":{"local:x":[]},"b":{"local:x":[]}}}}"#,
            #"{"electron-thread-read-state-v1":{"version":1,"unreadByIdentity":{"a":{"local:x":[],"local:y":[]}}}}"#,
            #"{"electron-thread-read-state-v1":{"version":1,"unreadByIdentity":{"a":{"local:x":null}}}}"#,
            #"{"electron-thread-read-state-v1":null,"electron-persisted-atom-state":{"unread-thread-ids-by-host-v1":{"local":[]}}}"#,
            #"{"electron-thread-read-state-v1":{"version":2,"unreadByIdentity":{"a":{"local:x":[]}}},"electron-persisted-atom-state":{"unread-thread-ids-by-host-v1":{"local":[]}}}"#,
            #"{"electron-persisted-atom-state":{"unread-thread-ids-by-host-v1":{"remote":[]}}}"#
        ]
        for json in invalid {
            XCTAssertNil(CodexDesktopReadState.parse(data: Data(json.utf8)), json)
        }
    }

    func testOnlyKnownCompletedCodexTasksAreReviewedAfterWriteGracePeriod() throws {
        let state = try XCTUnwrap(CodexDesktopReadState.parse(data: payload(unread: [])))
        XCTAssertFalse(state.hasReviewed(activity(state: .working), at: now))
        XCTAssertFalse(state.hasReviewed(activity(state: .waitingForApproval), at: now))
        XCTAssertFalse(state.hasReviewed(activity(provider: .claudeCode), at: now))
        XCTAssertFalse(state.hasReviewed(activity(threadID: nil), at: now))
        XCTAssertFalse(state.hasReviewed(activity(threadID: "cli-only-thread"), at: now))
        let justCompleted = activity(updatedAt: now)
        XCTAssertFalse(state.hasReviewed(justCompleted, at: now.addingTimeInterval(4)))
        XCTAssertTrue(state.hasReviewed(justCompleted, at: now.addingTimeInterval(5)))
    }

    @MainActor
    func testClaudeProcessDisappearanceIsNotInferredAsCompletion() {
        let monitor = CodexActivityMonitor(
            desktopStateURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("token-menu-missing-claude-state-\(UUID().uuidString).json")
        )
        let running = activity(state: .working, provider: .claudeCode, updatedAt: now)

        monitor.updateSnapshot(with: [running], connectionIsHealthy: true, at: now)
        monitor.updateSnapshot(with: [], connectionIsHealthy: true, at: now.addingTimeInterval(5))

        XCTAssertTrue(monitor.snapshot.activities.isEmpty)
    }

    @MainActor
    func testUnchangedActivityPollDoesNotAdvanceSnapshotTimestamp() {
        let monitor = CodexActivityMonitor(
            desktopStateURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("token-menu-unchanged-snapshot-\(UUID().uuidString).json")
        )
        let first = activity(
            id: "claude:123",
            state: .working,
            provider: .claudeCode,
            updatedAt: now
        )
        let sameActivityWithNewPollTime = activity(
            id: "claude:123",
            state: .working,
            provider: .claudeCode,
            updatedAt: now.addingTimeInterval(5)
        )

        monitor.updateSnapshot(with: [first], connectionIsHealthy: true, at: now)
        monitor.updateSnapshot(
            with: [sameActivityWithNewPollTime],
            connectionIsHealthy: true,
            at: now.addingTimeInterval(5)
        )

        XCTAssertEqual(monitor.snapshot.lastUpdated, now)
    }

    @MainActor
    func testCodexProcessDisappearanceStillInfersCompletion() {
        let monitor = CodexActivityMonitor(
            desktopStateURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("token-menu-missing-codex-state-\(UUID().uuidString).json")
        )
        let running = activity(state: .working, provider: .codex, updatedAt: now)

        monitor.updateSnapshot(with: [running], connectionIsHealthy: true, at: now)
        monitor.updateSnapshot(with: [], connectionIsHealthy: true, at: now.addingTimeInterval(5))

        XCTAssertEqual(monitor.snapshot.activities.first?.state, .completed)
    }

    @MainActor
    func testOpeningSpecificResultRemovesOnlyItsCompletionAndRetainedAliases() throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let stateURL = directory.appendingPathComponent("state.json")
        try payload(unread: ["thread-a", "thread-b"]).write(to: stateURL)
        let monitor = CodexActivityMonitor(desktopStateURL: stateURL)
        let first = activity(id: "rollout:turn-a", threadID: "thread-a")
        let alias = activity(id: "thread-a", threadID: "thread-a")
        let second = activity(id: "rollout:turn-b", threadID: "thread-b")
        let completed = [first, alias, second]

        monitor.updateSnapshot(with: completed, connectionIsHealthy: true, at: now)
        XCTAssertEqual(Set(monitor.snapshot.activities.map(\.id)), Set(completed.map(\.id)))
        // Merely using Codex leaves the per-thread unread list unchanged.
        monitor.updateSnapshot(with: [], connectionIsHealthy: true, at: now.addingTimeInterval(5))
        XCTAssertEqual(monitor.snapshot.activities.count, 3)

        try payload(unread: ["thread-b"]).write(to: stateURL)
        // This also covers retained rows no longer in the scanner's recent files.
        monitor.updateSnapshot(with: [], connectionIsHealthy: false, at: now.addingTimeInterval(10))
        XCTAssertEqual(monitor.snapshot.activities.map(\.id), [second.id])
        monitor.updateSnapshot(with: completed, connectionIsHealthy: false, at: now.addingTimeInterval(15))
        XCTAssertEqual(monitor.snapshot.activities.map(\.id), [second.id])
    }

    @MainActor
    func testRestartUsesAlreadySavedDesktopReadState() throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let stateURL = directory.appendingPathComponent("state.json")
        try payload(unread: ["thread-b"]).write(to: stateURL)
        let read = activity(id: "turn-a", threadID: "thread-a")
        let unread = activity(id: "turn-b", threadID: "thread-b")

        for _ in 0..<2 {
            let monitor = CodexActivityMonitor(desktopStateURL: stateURL)
            monitor.updateSnapshot(with: [read, unread], connectionIsHealthy: false, at: now)
            XCTAssertEqual(monitor.snapshot.activities.map(\.id), [unread.id])
        }
    }

    @MainActor
    func testMissingReadStateKeepsCompletionUntilValidDataArrives() throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let stateURL = directory.appendingPathComponent("state.json")
        let monitor = CodexActivityMonitor(desktopStateURL: stateURL)
        let completed = activity()
        monitor.updateSnapshot(with: [completed], connectionIsHealthy: false, at: now)
        XCTAssertEqual(monitor.snapshot.activities, [completed])
        try Data("{".utf8).write(to: stateURL)
        monitor.updateSnapshot(with: [], connectionIsHealthy: false, at: now)
        XCTAssertEqual(monitor.snapshot.activities, [completed])
        try payload(unread: []).write(to: stateURL)
        monitor.updateSnapshot(with: [], connectionIsHealthy: false, at: now)
        XCTAssertTrue(monitor.snapshot.activities.isEmpty)
    }

    @MainActor
    func testNewTurnInPreviouslyReviewedThreadRemainsUnread() throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let stateURL = directory.appendingPathComponent("state.json")
        try payload(unread: []).write(to: stateURL)
        let monitor = CodexActivityMonitor(desktopStateURL: stateURL)
        monitor.updateSnapshot(with: [activity()], connectionIsHealthy: true, at: now)
        XCTAssertTrue(monitor.snapshot.activities.isEmpty)

        let running = activity(state: .working, updatedAt: now)
        monitor.updateSnapshot(with: [running], connectionIsHealthy: true, at: now)
        XCTAssertEqual(monitor.snapshot.activities, [running])
        try payload(unread: ["thread-a"]).write(to: stateURL)
        let completed = activity(updatedAt: now)
        monitor.updateSnapshot(with: [completed], connectionIsHealthy: true, at: now.addingTimeInterval(10))
        XCTAssertEqual(monitor.snapshot.activities, [completed])
    }

    @MainActor
    func testLateUnreadWriteDoesNotLoseNewCompletion() throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let stateURL = directory.appendingPathComponent("state.json")
        try payload(unread: []).write(to: stateURL)
        let monitor = CodexActivityMonitor(desktopStateURL: stateURL)
        let completed = activity(updatedAt: now)
        monitor.updateSnapshot(with: [completed], connectionIsHealthy: true, at: now)
        XCTAssertEqual(monitor.snapshot.activities, [completed])
        try payload(unread: ["thread-a"]).write(to: stateURL)
        monitor.updateSnapshot(with: [completed], connectionIsHealthy: true, at: now.addingTimeInterval(5))
        XCTAssertEqual(monitor.snapshot.activities, [completed])
    }

    @MainActor
    func testPopoverReadSyncAppliesWithoutWaitingForNextActivityPoll() throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let stateURL = directory.appendingPathComponent("state.json")
        try payload(unread: ["thread-a", "thread-b"]).write(to: stateURL)
        let monitor = CodexActivityMonitor(desktopStateURL: stateURL)
        let first = activity(id: "turn-a", threadID: "thread-a")
        let second = activity(id: "turn-b", threadID: "thread-b")
        monitor.updateSnapshot(with: [first, second], connectionIsHealthy: false, at: now)

        try payload(unread: ["thread-b"]).write(to: stateURL)
        monitor.synchronizeDesktopReadState(at: now)
        XCTAssertEqual(monitor.snapshot.activities, [second])
        XCTAssertFalse(monitor.snapshot.isConnected)
    }

    @MainActor
    func testUnreadReceiptForReusedThreadIDOverridesPreviousAutomaticRead() throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let stateURL = directory.appendingPathComponent("state.json")
        try payload(unread: []).write(to: stateURL)
        let monitor = CodexActivityMonitor(desktopStateURL: stateURL)
        let completed = activity(id: "thread-a")
        monitor.updateSnapshot(with: [completed], connectionIsHealthy: true, at: now)
        XCTAssertTrue(monitor.snapshot.activities.isEmpty)

        // The next turn can start and finish before the next activity poll.
        try payload(unread: ["thread-a"]).write(to: stateURL)
        monitor.updateSnapshot(with: [completed], connectionIsHealthy: true, at: now.addingTimeInterval(30))
        XCTAssertEqual(monitor.snapshot.activities, [completed])
    }

    private func payload(unread: [String]) -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "electron-thread-read-state-v1": [
                "version": 1,
                "unreadByIdentity": ["account": ["local:machine": unread, "remote:other": ["thread-a"]]]
            ],
            "thread-project-assignments": ["thread-a": [:], "thread-b": [:]]
        ])
    }

    private func fixtureDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("token-menu-read-state-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func activity(
        id: String = "rollout:turn-a",
        threadID: String? = "thread-a",
        state: CodexActivityState = .completed,
        provider: AIProvider = .codex,
        updatedAt: Date? = nil
    ) -> CodexActivity {
        CodexActivity(
            id: id,
            title: "Same Project",
            chatGPTThreadID: threadID,
            provider: provider,
            state: state,
            startedAt: now.addingTimeInterval(-100),
            updatedAt: updatedAt ?? now.addingTimeInterval(-10)
        )
    }
}
