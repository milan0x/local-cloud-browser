import SwiftUI

@MainActor
final class TranscribeToolbarState: ObservableObject {
    @Published var pendingAction: Action?

    enum Action: Equatable {
        case createJob
        case deleteJob
    }

    func reset() {
        pendingAction = nil
    }
}

struct TranscribeToolbar: ToolbarContent {
    @ObservedObject var state: TranscribeToolbarState
    let isReadOnly: Bool
    let hasJob: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .createJob } label: {
                Label("Start Job", systemImage: "plus")
                    .toolbarHitTarget()
            }
            .help("Start Transcription Job")
            .disabled(isReadOnly)
        }
        ToolbarItem(placement: .primaryAction) {
            let disabled = !hasJob || isReadOnly
            Button { state.pendingAction = .deleteJob } label: {
                Label("Delete", systemImage: "trash")
                    .foregroundStyle(disabled ? .gray : .red)
                    .toolbarHitTarget()
            }
            .help("Delete Transcription Job")
            .disabled(disabled)
        }
    }
}
