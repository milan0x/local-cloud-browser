import Foundation

// MARK: - Transfer Direction

enum TransferDirection: Sendable {
    case upload
    case download
}

// MARK: - Transfer State

enum TransferState: Sendable, Equatable {
    case queued
    case active
    case completed
    case failed(String)
    case cancelled

    static func == (lhs: TransferState, rhs: TransferState) -> Bool {
        switch (lhs, rhs) {
        case (.queued, .queued): return true
        case (.active, .active): return true
        case (.completed, .completed): return true
        case (.cancelled, .cancelled): return true
        case (.failed(let a), .failed(let b)): return a == b
        default: return false
        }
    }

    var isFinished: Bool {
        switch self {
        case .queued, .active: return false
        case .completed, .failed, .cancelled: return true
        }
    }
}

// MARK: - Transfer Progress

/// Pure function for computing fraction completed, usable in tests.
enum TransferProgress {
    static func fractionCompleted(bytesTransferred: Int64, totalBytes: Int64) -> Double {
        guard totalBytes > 0 else { return 0 }
        return min(Double(bytesTransferred) / Double(totalBytes), 1.0)
    }
}
