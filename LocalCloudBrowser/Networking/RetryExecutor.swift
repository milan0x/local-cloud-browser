import Foundation

/// Executes an async operation with retry logic.
///
/// - Parameters:
///   - policy: Retry policy controlling max retries, backoff, and jitter
///   - operation: Description of the operation (for logging)
///   - onRetry: Called before each retry with attempt info (for UI updates)
///   - body: The async operation to execute
func withRetry<T: Sendable>(
    policy: RetryPolicy = .defaultPolicy,
    operation: String = "",
    onRetry: (@Sendable (RetryAttempt) -> Void)? = nil,
    body: @Sendable () async throws -> T
) async throws -> T {
    var attempt = 0

    while true {
        do {
            return try await body()
        } catch {
            try Task.checkCancellation()

            let statusCode: Int?
            let isNetworkError: Bool

            if let clientError = error as? CloudClientError {
                switch clientError {
                case .httpError(let code, _, _):
                    statusCode = code
                    isNetworkError = false
                case .networkError:
                    statusCode = nil
                    isNetworkError = true
                default:
                    statusCode = nil
                    isNetworkError = false
                }
            } else {
                statusCode = nil
                isNetworkError = (error as? URLError) != nil
            }

            let decision = RetryPolicy.shouldRetry(
                statusCode: statusCode,
                isNetworkError: isNetworkError,
                attempt: attempt,
                policy: policy
            )

            switch decision {
            case .retry(let delay):
                let retryAttempt = RetryAttempt(
                    attemptNumber: attempt + 1,
                    maxAttempts: policy.maxRetries,
                    error: error.localizedDescription,
                    nextRetryDate: Date().addingTimeInterval(delay)
                )
                onRetry?(retryAttempt)
                Log.info("Retrying \(operation) (attempt \(attempt + 1)/\(policy.maxRetries)) after \(String(format: "%.1f", delay))s", category: "Retry")
                try await Task.sleep(for: .milliseconds(Int(delay * 1000)))
                try Task.checkCancellation()
                attempt += 1

            case .doNotRetry:
                throw error
            }
        }
    }
}
