import Foundation

enum Log: Sendable {
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
        print("[\(timestamp)] [\(level)] [\(category)] \(message)")
    }
}
