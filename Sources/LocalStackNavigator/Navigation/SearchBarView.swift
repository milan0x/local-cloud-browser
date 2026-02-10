import SwiftUI

struct SearchBarView<TrailingContent: View>: View {
    @Binding var query: String
    var placeholder: String = "Filter..."
    @ViewBuilder var trailing: () -> TrailingContent

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 11))
            TextField(placeholder, text: $query)
                .textFieldStyle(.plain)
            trailing()
            Button {
                query = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(query.isEmpty ? 0 : 1)
        }
        .frame(width: 200)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        .padding(.leading, 8)
    }
}

extension SearchBarView where TrailingContent == EmptyView {
    init(query: Binding<String>, placeholder: String = "Filter...") {
        self._query = query
        self.placeholder = placeholder
        self.trailing = { EmptyView() }
    }
}
