import AppKit
import Foundation

@main
enum CodexUsageLauncher {
    static func main() {
        var mainAppURL = Bundle.main.bundleURL
        for _ in 0..<4 {
            mainAppURL.deleteLastPathComponent()
        }

        guard FileManager.default.fileExists(atPath: mainAppURL.path) else { return }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.arguments = ["--background-login"]
        let completion = DispatchSemaphore(value: 0)
        NSWorkspace.shared.openApplication(at: mainAppURL, configuration: configuration) { _, _ in
            completion.signal()
        }
        _ = completion.wait(timeout: .now() + 10)
    }
}

