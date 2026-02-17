import SwiftUI

// MARK: - Delete Confirmation Modifier

private struct DeleteConfirmationModifier<Item: Identifiable, M: View>: ViewModifier {
    @Binding var items: [Item]
    let title: (Int) -> String
    let actionLabel: String
    let message: ([Item]) -> M
    let onDelete: ([Item]) -> Void

    func body(content: Content) -> some View {
        content.alert(
            title(items.count),
            isPresented: Binding(
                get: { !items.isEmpty },
                set: { if !$0 { items = [] } }
            )
        ) {
            Button(actionLabel, role: .destructive) { onDelete(items) }
            Button("Cancel", role: .cancel) { items = [] }
        } message: {
            if !items.isEmpty {
                message(items)
            }
        }
    }
}

// MARK: - View Extensions

extension View {
    /// Delete confirmation with auto-generated "Delete Noun" / "Delete N Nouns" title.
    func deleteConfirmation<Item: Identifiable, M: View>(
        items: Binding<[Item]>,
        noun: String,
        pluralNoun: String? = nil,
        @ViewBuilder message: @escaping ([Item]) -> M,
        onDelete: @escaping ([Item]) -> Void
    ) -> some View {
        let plural = pluralNoun ?? "\(noun)s"
        return modifier(DeleteConfirmationModifier(
            items: items,
            title: { $0 == 1 ? "Delete \(noun)" : "Delete \($0) \(plural)" },
            actionLabel: "Delete",
            message: message,
            onDelete: onDelete
        ))
    }

    /// Delete confirmation with fully custom title and action label.
    func deleteConfirmation<Item: Identifiable, M: View>(
        items: Binding<[Item]>,
        title: @escaping (Int) -> String,
        actionLabel: String = "Delete",
        @ViewBuilder message: @escaping ([Item]) -> M,
        onDelete: @escaping ([Item]) -> Void
    ) -> some View {
        modifier(DeleteConfirmationModifier(
            items: items,
            title: title,
            actionLabel: actionLabel,
            message: message,
            onDelete: onDelete
        ))
    }
}

// MARK: - Batch Delete Helper

/// Performs a batch delete, returning the set of successfully deleted item IDs and the last error (if any).
@MainActor
func batchDelete<Item: Identifiable>(
    _ targets: [Item],
    delete: @MainActor (Item) async throws -> Void
) async -> (deleted: Set<Item.ID>, error: ServiceError?) {
    var deletedIDs: Set<Item.ID> = []
    var lastError: ServiceError?
    for item in targets {
        let itemID = item.id
        do {
            try await delete(item)
            deletedIDs.insert(itemID)
        } catch {
            lastError = error.asServiceError
        }
    }
    return (deletedIDs, lastError)
}
