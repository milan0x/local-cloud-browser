import Foundation
import os

struct ReadOnlyInterceptor {
    private static let logger = Logger(
        subsystem: "com.localcloudbrowser.app",
        category: "ReadOnlyInterceptor"
    )

    static func allowsRequest(method: String, isReadOnly: Bool) -> Bool {
        let mutatingMethods: Set<String> = ["POST", "PUT", "DELETE", "PATCH"]

        if isReadOnly && mutatingMethods.contains(method.uppercased()) {
            logger.warning("Blocked \(method) request — read-only mode is enabled")
            return false
        }

        return true
    }
}
