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

    // Action trigger — written by toolbar, consumed by browser view
    @Published var pendingAction: Action?

    enum Action: Equatable {
        case navigateBack
        case navigateForward
        case showPolicy
        case createFolder
        case upload
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
/// Conforms to CustomizableToolbarContent so toolbar(id:) can persist display mode natively.
struct S3Toolbar: CustomizableToolbarContent {
    @ObservedObject var state: S3ToolbarState
    let isReadOnly: Bool
    let hasBucket: Bool

    var body: some CustomizableToolbarContent {
        ToolbarItem(id: "s3-navigation", placement: .navigation) {
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
        ToolbarItem(id: "s3-policy", placement: .primaryAction) {
            Button { state.pendingAction = .showPolicy } label: {
                Label("Policy", systemImage: "doc.text")
            }
            .help("Bucket Policy")
            .disabled(!hasBucket)
        }
        ToolbarItem(id: "s3-create-folder", placement: .primaryAction) {
            Button { state.pendingAction = .createFolder } label: {
                Label("Folder", systemImage: "folder.badge.plus")
            }
            .help("Create Folder")
            .disabled(!hasBucket || isReadOnly)
        }
        ToolbarItem(id: "s3-upload", placement: .primaryAction) {
            Button { state.pendingAction = .upload } label: {
                Label("Upload", systemImage: "plus")
            }
            .help("Upload File")
            .disabled(!hasBucket || isReadOnly)
        }
        ToolbarItem(id: "s3-delete", placement: .primaryAction) {
            Button { state.pendingAction = .deleteSelected } label: {
                Label("Delete", systemImage: "trash")
            }
            .help("Delete Selected")
            .disabled(!hasBucket || isReadOnly || !state.hasSelection || state.isDeleting)
        }
    }
}
