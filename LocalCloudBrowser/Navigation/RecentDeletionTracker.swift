import SwiftUI

/// Tracks resources the user just deleted so the next ListX response can
/// filter them out, masking AWS's eventual-consistency window. Without
/// this, deleting (e.g.) a DynamoDB table would briefly continue to
/// return that table from ListTables — making it look like the delete
/// failed in the UI even though it succeeded server-side.
///
/// Usage in a list view:
/// ```
/// @StateObject private var recentDeletes = RecentDeletionTracker<String>()
///
/// // In the loader's fetch closure:
/// let fresh = try await service.listFoo()
/// return recentDeletes.filter(fresh, by: \.name)
///
/// // In the delete handler, after the API call succeeds:
/// recentDeletes.markDeleted(deletedNames)
/// loader.items.removeAll { recentDeletes.contains($0.name) }
/// loadFoo(force: true)
/// ```
@MainActor
final class RecentDeletionTracker<ID: Hashable>: ObservableObject {
    /// The set of recently-deleted identifiers. Public so SwiftUI can
    /// observe (via @Published) — list views typically don't read this
    /// directly, they call `filter(_:by:)` and `contains(_:)`.
    @Published private(set) var deletedIDs: Set<ID> = []

    /// How long an ID stays in the recently-deleted set before it's
    /// auto-cleared. 60 seconds is enough for SQS DeleteQueue's
    /// eventual-consistency window and comfortably covers most other
    /// AWS services. If the server starts returning a deleted resource
    /// again after this window, the user genuinely re-created it — show it.
    var ttl: TimeInterval = 60

    private var clearTasks: [ID: Task<Void, Never>] = [:]

    // Explicit deinit works around a Swift 6.3.1 SIL EarlyPerfInliner crash
    // on the implicit deinit of this generic class (Release/Archive only).
    // Also cancels pending sleep tasks so they don't fire after teardown.
    deinit {
        for task in clearTasks.values { task.cancel() }
    }

    /// Mark a set of IDs as recently deleted. They'll be auto-cleared
    /// after `ttl` seconds. Calling this for an already-tracked ID
    /// resets the timer, which is the desired behaviour.
    func markDeleted<S: Sequence>(_ ids: S) where S.Element == ID {
        let snapshot = Array(ids)
        guard !snapshot.isEmpty else { return }
        for id in snapshot {
            clearTasks[id]?.cancel()
            deletedIDs.insert(id)
            let ttl = self.ttl
            clearTasks[id] = Task { [weak self] in
                try? await Task.sleep(for: .seconds(ttl))
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    self?.deletedIDs.remove(id)
                    self?.clearTasks[id] = nil
                }
            }
        }
    }

    /// Forget a specific ID — typically because the user just re-created
    /// a resource with the same identifier and we want the new one to
    /// appear immediately.
    func clear(_ id: ID) {
        clearTasks[id]?.cancel()
        clearTasks[id] = nil
        deletedIDs.remove(id)
    }

    /// Forget all tracked IDs.
    func clearAll() {
        for task in clearTasks.values { task.cancel() }
        clearTasks.removeAll()
        deletedIDs.removeAll()
    }

    func contains(_ id: ID) -> Bool {
        deletedIDs.contains(id)
    }

    /// Filter a freshly-fetched list, removing any items whose ID falls in
    /// the recently-deleted set.
    func filter<T>(_ items: [T], by id: (T) -> ID) -> [T] {
        guard !deletedIDs.isEmpty else { return items }
        return items.filter { !deletedIDs.contains(id($0)) }
    }
}
