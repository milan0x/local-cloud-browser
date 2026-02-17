import SwiftUI

struct ListStatusBar: View {
    let totalCount: Int
    let selectedCount: Int
    let noun: String
    var pluralNoun: String?

    var body: some View {
        if totalCount > 0 {
            Divider()
            HStack {
                Text("\(totalCount) \(totalCount == 1 ? noun : (pluralNoun ?? noun + "s"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if selectedCount > 1 {
                    Text("(\(selectedCount) selected)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }
}
