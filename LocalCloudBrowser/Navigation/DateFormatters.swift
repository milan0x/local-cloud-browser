import Foundation

enum DateFormatters {
    nonisolated(unsafe) static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    nonisolated(unsafe) static let iso8601WithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Parse ISO8601 date string, trying fractional seconds first then standard
    static func parseISO8601(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        return iso8601WithFractional.date(from: string) ?? iso8601.date(from: string)
    }

    /// Parse a value that may be a Double timestamp or an ISO8601 string
    static func parseDateValue(_ value: Any?) -> Date? {
        if let ts = value as? Double {
            return Date(timeIntervalSince1970: ts)
        }
        if let str = value as? String {
            return parseISO8601(str)
        }
        return nil
    }
}
