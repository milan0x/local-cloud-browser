import SwiftUI

struct SearchableDropdownItem: Identifiable {
    let id: String
    let label: String
    let description: String
}

struct SearchableDropdown: View {
    let items: [SearchableDropdownItem]
    @Binding var selectedID: String
    var placeholder: String = "Select..."

    @State private var isOpen = false
    @State private var filter = ""

    private var selectedItem: SearchableDropdownItem? {
        items.first { $0.id == selectedID }
    }

    private var filteredItems: [SearchableDropdownItem] {
        let query = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return items }
        return items.filter {
            $0.label.lowercased().contains(query)
                || $0.description.lowercased().contains(query)
        }
    }

    var body: some View {
        Button {
            filter = ""
            isOpen.toggle()
        } label: {
            HStack(spacing: 4) {
                if let item = selectedItem {
                    Text(item.label)
                        .foregroundColor(Color(.labelColor))
                    Text("— \(item.description)")
                        .foregroundColor(Color(.secondaryLabelColor))
                        .lineLimit(1)
                } else {
                    Text(placeholder)
                        .foregroundColor(Color(.tertiaryLabelColor))
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .foregroundColor(Color(.secondaryLabelColor))
                    .font(.caption)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(.background)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.15))
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            popoverContent
        }
    }

    private var popoverContent: some View {
        VStack(spacing: 0) {
            TextField("Filter...", text: $filter)
                .textFieldStyle(.roundedBorder)
                .padding(8)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredItems) { item in
                            itemRow(item)
                                .id(item.id)
                        }
                    }
                }
                .frame(maxHeight: 260)
                .onAppear {
                    if !selectedID.isEmpty {
                        proxy.scrollTo(selectedID, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 320)
    }

    private func itemRow(_ item: SearchableDropdownItem) -> some View {
        Button {
            selectedID = item.id
            isOpen = false
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
                    .opacity(item.id == selectedID ? 1 : 0)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.label)
                        .font(.body)
                    Text(item.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(item.id == selectedID ? Color.accentColor.opacity(0.12) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}
