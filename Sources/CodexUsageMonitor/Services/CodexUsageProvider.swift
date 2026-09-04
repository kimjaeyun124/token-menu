import Foundation
import os

protocol CodexUsageProviding: Sendable {
    func fetchUsage() async throws -> CodexUsage
}

enum CodexUsageError: LocalizedError {
    case timedOut
    case malformedResponse
    case serverUnavailable
    case authenticationRequired

    var errorDescription: String? {
        switch self {
        case .timedOut: return "Codex did not respond in time."
        case .malformedResponse: return "Codex returned unsupported usage information."
        case .serverUnavailable: return "Codex usage information is temporarily unavailable."
        case .authenticationRequired: return "Sign in to Codex, then refresh."
        }
    }
}

struct CodexRateLimitParser {
    private static let logger = Logger(subsystem: "com.kimjaeyun.codexusagemonitor", category: "UsageParser")

    private struct Envelope: Decodable {
        let id: Int?
        let result: RateLimitResult?
        let error: RPCError?
    }

    private struct RPCError: Decodable {
        let code: Int?
    }

    private struct RateLimitResult: Decodable {
        let rateLimits: Snapshot
        let rateLimitsByLimitId: [String: Snapshot]?
    }

    private struct Snapshot: Decodable {
        let limitId: String?
        let primary: Window?
        let secondary: Window?
    }

    private struct Window: Decodable {
        let usedPercent: Double
        let windowDurationMins: Int?
        let resetsAt: Double?
    }

    static func responseID(in data: Data) -> Int? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let id = object["id"] as? NSNumber
        else { return nil }
        return id.intValue
    }

    static func parse(responseData: Data, now: Date = Date()) throws -> CodexUsage {
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: responseData)
        } catch {
            logger.error("Rejected malformed rate-limit JSON; response content omitted")
            throw CodexUsageError.malformedResponse
        }

        if let rpcError = envelope.error {
            if rpcError.code == 401 || rpcError.code == -32_001 {
                throw CodexUsageError.authenticationRequired
            }
            throw CodexUsageError.serverUnavailable
        }

        guard let result = envelope.result else {
            logger.error("Rate-limit response did not contain a result")
            throw CodexUsageError.malformedResponse
        }

        let snapshot = result.rateLimitsByLimitId?["codex"]
            ?? result.rateLimitsByLimitId?.values.first(where: { $0.limitId == "codex" })
            ?? result.rateLimits
        let windows = [snapshot.primary, snapshot.secondary].compactMap { $0 }
        let fiveHourWindow = windows.first { $0.windowDurationMins == 300 }
        let weeklyWindow = windows.first { $0.windowDurationMins == 10_080 }

        let fiveHourRemainingPercent = validatedRemaining(
            from: fiveHourWindow?.usedPercent,
            field: "5-hour used percent"
        )
        let weeklyRemainingPercent = validatedRemaining(
            from: weeklyWindow?.usedPercent,
            field: "weekly used percent"
        )

        if fiveHourWindow == nil {
            logger.error("5-hour rate-limit window is unavailable or has an unsupported duration")
        }
        if weeklyWindow == nil {
            logger.error("Weekly rate-limit window is unavailable or has an unsupported duration")
        }

        return CodexUsage(
            fiveHourRemainingPercent: fiveHourRemainingPercent,
            weeklyRemainingPercent: weeklyRemainingPercent,
            fiveHourResetDate: validatedDate(from: fiveHourWindow?.resetsAt, field: "5-hour reset"),
            weeklyResetDate: validatedDate(from: weeklyWindow?.resetsAt, field: "weekly reset"),
            lastUpdated: now,
            source: "Codex app-server account/rateLimits/read"
        )
    }

    private static func validatedRemaining(from usedPercent: Double?, field: String) -> Double? {
        guard let usedPercent else { return nil }
        guard let remainingPercent = Double.remaining(fromUsedPercent: usedPercent) else {
            logger.error("Rejected invalid \(field, privacy: .public); value omitted")
            return nil
        }
        return remainingPercent
    }

    private static func validatedDate(from epochSeconds: Double?, field: String) -> Date? {
        guard let epochSeconds else { return nil }
        guard epochSeconds.isFinite, epochSeconds > 0 else {
            logger.error("Rejected invalid \(field, privacy: .public); value omitted")
            return nil
        }
        return Date(timeIntervalSince1970: epochSeconds)
    }
}

actor CodexAppServerUsageProvider: CodexUsageProviding {
    private let detector: CodexDetector

    init(detector: CodexDetector = CodexDetector()) {
        self.detector = detector
    }

    func fetchUsage() async throws -> CodexUsage {
        let codex = try detector.detect()
        return try await AppServerRequest(executableURL: codex.executableURL).perform()
    }
}

private final class AppServerRequest: @unchecked Sendable {
    private let executableURL: URL
    private let process = Process()
    private let inputPipe = Pipe()
    private let outputPipe = Pipe()
    private let errorPipe = Pipe()
    private let lock = NSLock()
    private var outputBuffer = Data()
    private var completed = false
    private var sentUsageRequest = false
    private var continuation: CheckedContinuation<CodexUsage, Error>?

    init(executableURL: URL) {
        self.executableURL = executableURL
    }

    func perform() async throws -> CodexUsage {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            configureProcess()

            do {
                try process.run()
                try send([
                    "id": 1,
                    "method": "initialize",
                    "params": [
                        "clientInfo": [
                            "name": "codex-usage-monitor",
                            "version": "1.0.0"
                        ],
                        "capabilities": [:]
                    ]
                ])
            } catch {
                finish(.failure(CodexUsageError.serverUnavailable))
                return
            }

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 20) { [weak self] in
                self?.finish(.failure(CodexUsageError.timedOut))
            }
        }
    }

    private func configureProcess() {
        process.executableURL = executableURL
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.consume(data)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }
        process.terminationHandler = { [weak self] _ in
            self?.finish(.failure(CodexUsageError.serverUnavailable))
        }
    }

    private func consume(_ data: Data) {
        lock.lock()
        outputBuffer.append(data)
        let newline = Data([0x0A])
        var lines: [Data] = []
        while let range = outputBuffer.range(of: newline) {
            lines.append(outputBuffer.subdata(in: outputBuffer.startIndex..<range.lowerBound))
            outputBuffer.removeSubrange(outputBuffer.startIndex...range.lowerBound)
        }
        lock.unlock()

        for line in lines where !line.isEmpty {
            handle(line)
        }
    }

    private func handle(_ line: Data) {
        switch CodexRateLimitParser.responseID(in: line) {
        case 1:
            lock.lock()
            let shouldSend = !sentUsageRequest && !completed
            sentUsageRequest = true
            lock.unlock()
            guard shouldSend else { return }

            do {
                try send(["method": "initialized"])
                try send(["id": 2, "method": "account/rateLimits/read"])
            } catch {
                finish(.failure(CodexUsageError.serverUnavailable))
            }
        case 2:
            do {
                finish(.success(try CodexRateLimitParser.parse(responseData: line)))
            } catch {
                finish(.failure(error))
            }
        default:
            break
        }
    }

    private func send(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try inputPipe.fileHandleForWriting.write(contentsOf: data)
    }

    private func finish(_ result: Result<CodexUsage, Error>) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        let continuation = continuation
        self.continuation = nil
        lock.unlock()

        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        try? inputPipe.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        continuation?.resume(with: result)
    }
}
