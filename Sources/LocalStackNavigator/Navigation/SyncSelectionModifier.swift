import SwiftUI

struct SyncSelectionModifier<Item: Identifiable>: ViewModifier where Item.ID: Hashable {
    let selectedIDs: Set<Item.ID>
    let items: [Item]
    @Binding var activeItem: Item?

    func body(content: Content) -> some View {
        content
            .onChange(of: selectedIDs) {
                if selectedIDs.count == 1, let id = selectedIDs.first {
                    activeItem = items.first { $0.id == id }
                } else {
                    activeItem = nil
                }
            }
    }
}

extension View {
    func syncSelection<Item: Identifiable>(
        _ selectedIDs: Set<Item.ID>,
        items: [Item],
        activeItem: Binding<Item?>
    ) -> some View where Item.ID: Hashable {
        modifier(SyncSelectionModifier(selectedIDs: selectedIDs, items: items, activeItem: activeItem))
    }
}
