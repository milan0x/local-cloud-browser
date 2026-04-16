import SwiftUI

struct TransferToolbarButton: View {
    @EnvironmentObject private var transferManager: TransferManager
    @State private var showPopover = false

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            Image(systemName: "arrow.up.arrow.down.circle")
        }
        .overlay(alignment: .topTrailing) {
            if transferManager.hasActiveTransfers {
                Text("\(transferManager.totalFileCount)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.blue))
                    .offset(x: 6, y: -6)
                    .allowsHitTesting(false)
            }
        }
        .opacity(transferManager.items.isEmpty ? 0.5 : 1.0)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            TransferPopoverView()
        }
        .help("File transfers")
        .accessibilityLabel("File transfers")
    }
}
