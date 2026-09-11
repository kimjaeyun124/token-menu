import Foundation
import Network
import SwiftUI

enum CodexActivityState: Equatable, Sendable {
    case working
    case waitingForApproval
    case waitingForInput
    case error

    var localizationKey: String {
        switch self {
        case .working: return "activity.working"
        case .waitingForApproval: return "activity.waiting_approval"
        case .waitingForInput: return "activity.waiting_input"
        case .error: return "activity.error"
        }
    }
}

struct CodexActivity: Equatable, Sendable, Identifiable {
    let id: String
    let title: String?
    let state: CodexActivityState
    let startedAt: Date?
    let updatedAt: Date
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

@MainActor
final class CodexActivityMonitor: ObservableObject {
    @Published private(set) var snapshot = CodexActivitySnapshot.unavailable()

    private var task: Task<Void, Never>?
    private let socketPath: String

    init(socketPath: String = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/app-server-control/app-server-control.sock").path) {
        self.socketPath = socketPath
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
        snapshot = .unavailable()
    }

    var primaryElapsedSeconds: TimeInterval? {
        guard let startedAt = snapshot.primary?.startedAt else { return nil }
        return max(0, Date().timeIntervalSince(startedAt))
    }

    private func monitorLoop() async {
        while !Task.isCancelled {
            do {
                let client = try await CodexActivityClient(socketPath: socketPath)
                let activities = try await client.fetchActiveActivities()
                snapshot = CodexActivitySnapshot(
                    activities: activities,
                    isConnected: true,
                    lastUpdated: Date()
                )
                await client.close()
                try await Task.sleep(for: .seconds(5))
            } catch is CancellationError {
                return
            } catch {
                snapshot = CodexActivitySnapshot.unavailable()
                try? await Task.sleep(for: .seconds(30))
            }
        }
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
            params: ["archived": false, "limit": 20, "useStateDbOnly": true]
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
