import Testing
@testable import LocalCloudBrowser

@Suite("Transfer Types")
struct TransferTypesTests {

    // MARK: - TransferState Equality

    @Test("TransferState equality for simple cases")
    func stateEquality() {
        #expect(TransferState.queued == .queued)
        #expect(TransferState.active == .active)
        #expect(TransferState.completed == .completed)
        #expect(TransferState.cancelled == .cancelled)
    }

    @Test("TransferState equality for failed with same message")
    func failedEqualitySame() {
        #expect(TransferState.failed("timeout") == .failed("timeout"))
    }

    @Test("TransferState inequality for failed with different messages")
    func failedEqualityDifferent() {
        #expect(TransferState.failed("a") != .failed("b"))
    }

    @Test("TransferState inequality across cases")
    func crossCaseInequality() {
        #expect(TransferState.queued != .active)
        #expect(TransferState.completed != .cancelled)
    }

    // MARK: - isFinished

    @Test("isFinished returns false for active states")
    func isFinishedFalse() {
        #expect(!TransferState.queued.isFinished)
        #expect(!TransferState.active.isFinished)
    }

    @Test("isFinished returns true for terminal states")
    func isFinishedTrue() {
        #expect(TransferState.completed.isFinished)
        #expect(TransferState.failed("err").isFinished)
        #expect(TransferState.cancelled.isFinished)
    }

    // MARK: - TransferProgress

    @Test("fractionCompleted returns 0 when totalBytes is 0")
    func fractionZeroTotal() {
        #expect(TransferProgress.fractionCompleted(bytesTransferred: 100, totalBytes: 0) == 0)
    }

    @Test("fractionCompleted normal range")
    func fractionNormal() {
        let result = TransferProgress.fractionCompleted(bytesTransferred: 50, totalBytes: 100)
        #expect(result == 0.5)
    }

    @Test("fractionCompleted caps at 1.0")
    func fractionCapped() {
        let result = TransferProgress.fractionCompleted(bytesTransferred: 200, totalBytes: 100)
        #expect(result == 1.0)
    }
}
