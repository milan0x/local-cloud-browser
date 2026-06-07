import SwiftUI

struct SupportHeartButton: View {
    @State private var isHovering = false
    @State private var showDonation = false

    var body: some View {
        Button {
            showDonation = true
        } label: {
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
        .onHover { hovering in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                isHovering = hovering
            }
        }
        .padding(16)
        .sheet(isPresented: $showDonation) {
            DonationView()
        }
    }
}
