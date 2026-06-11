import SwiftUI

struct SupportHeartButton: View {
    let onTap: () -> Void
    /// Right-click → "Hide Forever". Donations stay reachable from the
    /// Donation menu, so this is a one-way dismissal by design.
    let onHideForever: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                if isHovering {
                    Text("Support development")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .fixedSize()
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
            .overlay(
                Capsule().strokeBorder(.separator.opacity(0.6), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .help("Support development")
        .accessibilityLabel("Support development")
        .contextMenu {
            Button("Hide Forever") {
                onHideForever()
            }
            Text("Donations stay available in the Donation menu.")
        }
        .onHover { hovering in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                isHovering = hovering
            }
        }
        .padding(16)
    }
}
