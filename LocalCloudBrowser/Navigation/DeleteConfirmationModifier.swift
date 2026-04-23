import SwiftUI

// MARK: - Delete Confirmation Modifier

private struct DeleteConfirmationModifier<Item: Identifiable, M: View>: ViewModifier {
    @Binding var items: [Item]
    let title: (Int) -> String
    let actionLabel: String
    let message: ([Item]) -> M
    let onDelete: ([Item]) -> Void

    func body(content: Content) -> some View {
        content
            .alert(
                items.count == 1 ? title(1) : "",
                isPresented: Binding(
                    get: { items.count == 1 },
                    set: { if !$0 { items = [] } }
                )
            ) {
                Button(actionLabel, role: .destructive) {
                    let snapshot = items
                    items = []
                    onDelete(snapshot)
                }
                Button("Cancel", role: .cancel) { items = [] }
            } message: {
                if items.count == 1 {
                    message(items)
                }
            }
            .sheet(isPresented: Binding(
                get: { items.count > 1 },
                set: { if !$0 { items = [] } }
            )) {
                DeleteConfirmationSheet(
                    title: title(items.count),
                    actionLabel: actionLabel,
                    onDelete: {
                        let snapshot = items
                        items = []
                        onDelete(snapshot)
                    },
                    onCancel: { items = [] }
                ) {
                    message(items)
                }
            }
    }
}

// MARK: - Delete Confirmation Sheet

private struct DeleteConfirmationSheet<M: View>: View {
    let title: String
    let actionLabel: String
    let onDelete: () -> Void
    let onCancel: () -> Void
    @ViewBuilder let message: () -> M

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "trash")
                    .font(.system(size: 28))
                    .foregroundStyle(.red)
                Text(title)
                    .font(.headline)
            }
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            // Scrollable message area
            ScrollView {
                message()
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .frame(maxHeight: 200)

            Divider()

            // Buttons
            HStack {
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(actionLabel, role: .destructive) { onDelete() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 360)
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
