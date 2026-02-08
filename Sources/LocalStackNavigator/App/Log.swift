import Foundation

enum Log {
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func info(_ message: String, category: String = "App") {
        emit(level: "INFO", message: message, category: category)
    }

    static func warn(_ message: String, category: String = "App") {
        emit(level: "WARN", message: message, category: category)
    }

    static func error(_ message: String, category: String = "App") {
        emit(level: "ERROR", message: message, category: category)
    }

    private static func emit(level: String, message: String, category: String) {
        let timestamp = dateFormatter.string(from: Date())
        print("[\(timestamp)] [\(level)] [\(category)] \(message)")
    }
}
