import Foundation

enum PercentageFormatter {
    /// Formats a service-provided remaining percentage as a whole number.
    /// Invalid values stay unavailable instead of becoming zero.
    static func string(for value: Double?) -> String? {
        guard let value, value.isFinite, (0...100).contains(value) else { return nil }

        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        formatter.roundingMode = .halfUp
        guard let formatted = formatter.string(from: NSNumber(value: value)) else { return nil }
        return "\(formatted)%"
    }

    static func unavailable(_ display: UnavailableDisplay) -> String {
        switch display {
        case .dashes: return "--%"
        case .notAvailable: return "N/A"
        case .hidden: return ""
        }
    }
}
