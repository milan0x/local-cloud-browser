import Foundation
import os

enum Log: Sendable {
    private static let logger = Logger(subsystem: "com.milan.localcloudbrowser", category: "app")

    nonisolated static func info(_ message: String, category: String = "App") {
        emit(level: "INFO", message: message, category: category)
    }

    nonisolated static func warn(_ message: String, category: String = "App") {
        emit(level: "WARN", message: message, category: category)
    }

    nonisolated static func error(_ message: String, category: String = "App") {
        emit(level: "ERROR", message: message, category: category)
    }

    private nonisolated static func emit(level: String, message: String, category: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let timestamp = formatter.string(from: Date())
        let line = "[\(timestamp)] [\(level)] [\(category)] \(message)"
        print(line)
        // Also emit via os_log so `log show --predicate 'subsystem == "..."'` can find it.
        logger.log("\(line, privacy: .public)")
    }
}
