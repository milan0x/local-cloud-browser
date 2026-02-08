import SwiftUI

struct ModulePlaceholderView: View {
    let serviceName: String
    let systemImage: String
    let description: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(serviceName)
                .font(.title)
                .fontWeight(.semibold)
            Text(description)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            Text("Coming Soon")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
