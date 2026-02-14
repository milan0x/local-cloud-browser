import SwiftUI

@MainActor
final class DynamoDBToolbarState: ObservableObject {
    @Published var pendingAction: Action?

    enum Action: Equatable {
        case showAttributes
        case putItem
        case createTable
        case deleteSelected
    }

    func reset() {
        pendingAction = nil
    }
}

struct DynamoDBToolbar: ToolbarContent {
    @ObservedObject var state: DynamoDBToolbarState
    let isReadOnly: Bool
    let hasTable: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .showAttributes } label: {
                Label("Attributes", systemImage: "info.circle")
                    .toolbarHitTarget()
            }
            .help("Table Attributes")
            .disabled(!hasTable)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .putItem } label: {
                Label("Put Item", systemImage: "plus.square")
                    .toolbarHitTarget()
            }
            .help("Put Item")
            .disabled(!hasTable || isReadOnly)
        }
    }
}
