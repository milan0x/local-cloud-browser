import SwiftUI

/// Two-way bridge between S3ObjectBrowserView (state producer) and its parent (toolbar owner).
@MainActor
final class S3ToolbarState: ObservableObject {
    // Display state — written by browser view, read by toolbar
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var hasSelection = false
    @Published var isDeleting = false

    // Bucket list interaction — clears browser object selection
    @Published var clearSelectionTrigger = 0

    // Double-click bucket — resets browser to bucket root
    @Published var resetToRootTrigger = 0

    // Action trigger — written by toolbar, consumed by browser view
    @Published var pendingAction: Action?

    enum Action: Equatable {
        case navigateBack
        case navigateForward
        case showPolicy
        case createFolder
        case uploadFile
        case uploadFolder
        case refresh
        case deleteSelected
    }

    func reset() {
        canGoBack = false
        canGoForward = false
        isLoading = false
        hasSelection = false
        isDeleting = false
        pendingAction = nil
    }
}

/// Reusable toolbar content for S3 browser views.
struct S3Toolbar: ToolbarContent {
    @ObservedObject var state: S3ToolbarState
    let isReadOnly: Bool
    let hasBucket: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 4) {
                Button { state.pendingAction = .navigateBack } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!hasBucket || !state.canGoBack || state.isLoading)
                .help("Back")
                Button { state.pendingAction = .navigateForward } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!hasBucket || !state.canGoForward || state.isLoading)
                .help("Forward")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .showPolicy } label: {
                Label("Policy", systemImage: "doc.text")
                    .toolbarHitTarget()
            }
            .help("Bucket Policy")
            .disabled(!hasBucket)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .createFolder } label: {
                Label("Folder", systemImage: "folder.badge.plus")
                    .toolbarHitTarget()
            }
            .help("Create Folder")
            .disabled(!hasBucket || isReadOnly)
        }
        // (No Refresh button here — the global toolbar refresh in ContentView
        // already fans out to the S3 views via `.onAutoRefresh`, and two
        // identical refresh icons in one toolbar read as a bug.)
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Upload File") { state.pendingAction = .uploadFile }
                Button("Upload Folder") { state.pendingAction = .uploadFolder }
            } label: {
                Label("Upload", systemImage: "icloud.and.arrow.up")
                    .toolbarHitTarget()
            }
            .help("Upload")
            .disabled(!hasBucket || isReadOnly)
        }
        ToolbarItem(placement: .primaryAction) {
            let disabled = !hasBucket || isReadOnly || !state.hasSelection || state.isDeleting
            Button { state.pendingAction = .deleteSelected } label: {
                Label("Delete", systemImage: "trash")
                    .foregroundStyle(disabled ? .gray : .red)
                    .toolbarHitTarget()
            }
            .help("Delete Selected")
            .disabled(disabled)
        }
    }
}
