import SwiftUI

struct ListStatusBar: View {
    let totalCount: Int
    let selectedCount: Int
    let noun: String
    var pluralNoun: String?
    var hasMorePages: Bool = false

    var body: some View {
        if totalCount > 0 {
            Divider()
            HStack(spacing: 6) {
                Text("\(totalCount)\(hasMorePages ? "+" : "") \(totalCount == 1 && !hasMorePages ? noun : (pluralNoun ?? noun + "s"))")
                    .font(.callout)
                    .foregroundStyle(.primary)
                if selectedCount > 1 {
                    Text("(\(selectedCount) selected)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }
}
