import Foundation

enum AppLocationDiagnostics {
    static var isAppTranslocated: Bool {
        isAppTranslocated(bundleURL: Bundle.main.bundleURL)
    }

    static func isAppTranslocated(bundleURL: URL) -> Bool {
        bundleURL.standardizedFileURL.path.contains("/AppTranslocation/")
    }
}
