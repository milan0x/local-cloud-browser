import Foundation

// MARK: - Retry Decision

enum RetryDecision: Sendable, Equatable {
    case retry(after: TimeInterval)
    case doNotRetry(reason: String)
}

// MARK: - Retry Policy

struct RetryPolicy: Sendable {
    let maxRetries: Int
    let baseDelay: TimeInterval
    let maxDelay: TimeInterval
    let jitterFactor: Double

    init(
        maxRetries: Int = 3,
        baseDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 30.0,
        jitterFactor: Double = 0.25
    ) {
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.jitterFactor = jitterFactor
    }

    static let defaultPolicy = RetryPolicy()
    static let noRetry = RetryPolicy(maxRetries: 0)

    /// Computes the delay for a given attempt using exponential backoff with jitter.
    /// Attempt numbering starts at 0 (first retry).
    func delay(for attempt: Int) -> TimeInterval {
        let exponential = baseDelay * pow(2.0, Double(attempt))
        let capped = min(exponential, maxDelay)
        let jitter = capped * jitterFactor * Double.random(in: -1...1)
        return max(0, capped + jitter)
    }

    // MARK: - Retry eligibility

    /// HTTP status codes that are safe to retry (server-side transient errors).
    private static let retryableStatusCodes: Set<Int> = [500, 502, 503, 504]

    /// Determines whether an operation should be retried.
    static func shouldRetry(
        statusCode: Int?,
        isNetworkError: Bool,
        attempt: Int,
        policy: RetryPolicy
    ) -> RetryDecision {
        guard attempt < policy.maxRetries else {
            return .doNotRetry(reason: "Exceeded maximum retries (\(policy.maxRetries))")
        }

        if isNetworkError {
            return .retry(after: policy.delay(for: attempt))
        }

        if let code = statusCode {
            if retryableStatusCodes.contains(code) {
                return .retry(after: policy.delay(for: attempt))
            }
            return .doNotRetry(reason: "HTTP \(code) is not retryable")
        }

        return .doNotRetry(reason: "Unknown error type")
    }
}

// MARK: - Retry Attempt (UI state)

struct RetryAttempt: Sendable, Identifiable {
    let id: UUID
    let attemptNumber: Int
    let maxAttempts: Int
    let error: String
    let nextRetryDate: Date?

    init(attemptNumber: Int, maxAttempts: Int, error: String, nextRetryDate: Date?) {
        self.id = UUID()
        self.attemptNumber = attemptNumber
        self.maxAttempts = maxAttempts
        self.error = error
        self.nextRetryDate = nextRetryDate
    }
}
