import Foundation

struct ProcessOutput: Sendable {
    let standardOutput: String
    let terminationStatus: Int32
}

enum ProcessRunnerError: LocalizedError {
    case launchFailed
    case nonZeroExit(Int32)

    var errorDescription: String? {
        switch self {
        case .launchFailed: return "The command could not be launched."
        case .nonZeroExit: return "The command did not complete successfully."
        }
    }
}

enum ProcessRunner {
    static func run(executableURL: URL, arguments: [String]) throws -> ProcessOutput {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw ProcessRunnerError.launchFailed
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        _ = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ProcessRunnerError.nonZeroExit(process.terminationStatus)
        }

        return ProcessOutput(
            standardOutput: String(decoding: outputData, as: UTF8.self),
            terminationStatus: process.terminationStatus
        )
    }
}

