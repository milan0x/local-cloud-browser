import SwiftUI

struct SearchBarView<TrailingContent: View>: View {
    @Binding var query: String
    var placeholder: String = "Filter..."
    var focusTrigger: Int = 0
    @ViewBuilder var trailing: () -> TrailingContent

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 11))
            TextField(placeholder, text: $query)
                .textFieldStyle(.plain)
                .focused($isFocused)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        .onChange(of: focusTrigger) {
            isFocused = true
        }
    }
}

extension SearchBarView where TrailingContent == EmptyView {
    init(query: Binding<String>, placeholder: String = "Filter...", focusTrigger: Int = 0) {
        self._query = query
        self.placeholder = placeholder
        self.focusTrigger = focusTrigger
        self.trailing = { EmptyView() }
    }
}
