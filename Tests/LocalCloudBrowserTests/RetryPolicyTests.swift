import Testing
@testable import LocalCloudBrowser

@Suite("Retry Policy")
struct RetryPolicyTests {

    // MARK: - Delay Calculation

    @Test("Exponential backoff doubles each attempt")
    func exponentialBackoff() {
        let policy = RetryPolicy(maxRetries: 5, baseDelay: 1.0, maxDelay: 100.0, jitterFactor: 0)
        // Without jitter, delay = baseDelay * 2^attempt
        #expect(policy.delay(for: 0) == 1.0)
        #expect(policy.delay(for: 1) == 2.0)
        #expect(policy.delay(for: 2) == 4.0)
        #expect(policy.delay(for: 3) == 8.0)
    }

    @Test("Delay is capped at maxDelay")
    func maxDelayCap() {
        let policy = RetryPolicy(maxRetries: 10, baseDelay: 1.0, maxDelay: 5.0, jitterFactor: 0)
        #expect(policy.delay(for: 10) == 5.0) // 2^10 = 1024, capped at 5
    }

    @Test("Delay with jitter stays within bounds")
    func jitterBounds() {
        let policy = RetryPolicy(maxRetries: 3, baseDelay: 10.0, maxDelay: 100.0, jitterFactor: 0.25)
        for _ in 0..<20 {
            let delay = policy.delay(for: 0)
            // Base = 10, jitter = ±25% → range [7.5, 12.5]
            #expect(delay >= 7.5)
            #expect(delay <= 12.5)
        }
    }

    @Test("Delay is never negative")
    func nonNegativeDelay() {
        let policy = RetryPolicy(maxRetries: 3, baseDelay: 0.1, maxDelay: 1.0, jitterFactor: 0.25)
        for attempt in 0..<10 {
            #expect(policy.delay(for: attempt) >= 0)
        }
    }

    // MARK: - shouldRetry

    @Test("Retries on 500 status code")
    func retry500() {
        let decision = RetryPolicy.shouldRetry(statusCode: 500, isNetworkError: false, attempt: 0, policy: .defaultPolicy)
        if case .retry = decision {
            // expected
        } else {
            Issue.record("Expected retry for 500")
        }
    }

    @Test("Retries on 502, 503, 504")
    func retryServerErrors() {
        for code in [502, 503, 504] {
            let decision = RetryPolicy.shouldRetry(statusCode: code, isNetworkError: false, attempt: 0, policy: .defaultPolicy)
            if case .retry = decision {
                // expected
            } else {
                Issue.record("Expected retry for \(code)")
            }
        }
    }

    @Test("Does not retry on 400")
    func noRetry400() {
        let decision = RetryPolicy.shouldRetry(statusCode: 400, isNetworkError: false, attempt: 0, policy: .defaultPolicy)
        if case .doNotRetry = decision {
            // expected
        } else {
            Issue.record("Expected doNotRetry for 400")
        }
    }

    @Test("Does not retry on 403")
    func noRetry403() {
        let decision = RetryPolicy.shouldRetry(statusCode: 403, isNetworkError: false, attempt: 0, policy: .defaultPolicy)
        if case .doNotRetry = decision {
            // expected
        } else {
            Issue.record("Expected doNotRetry for 403")
        }
    }

    @Test("Retries on network error")
    func retryNetworkError() {
        let decision = RetryPolicy.shouldRetry(statusCode: nil, isNetworkError: true, attempt: 0, policy: .defaultPolicy)
        if case .retry = decision {
            // expected
        } else {
            Issue.record("Expected retry for network error")
        }
    }

    @Test("Does not retry when max retries exceeded")
    func maxRetriesExceeded() {
        let decision = RetryPolicy.shouldRetry(statusCode: 500, isNetworkError: false, attempt: 3, policy: .defaultPolicy)
        if case .doNotRetry = decision {
            // expected
        } else {
            Issue.record("Expected doNotRetry when max retries exceeded")
        }
    }

    @Test("noRetry policy never retries")
    func noRetryPolicy() {
        let decision = RetryPolicy.shouldRetry(statusCode: 500, isNetworkError: false, attempt: 0, policy: .noRetry)
        if case .doNotRetry = decision {
            // expected
        } else {
            Issue.record("Expected doNotRetry with noRetry policy")
        }
    }
}
