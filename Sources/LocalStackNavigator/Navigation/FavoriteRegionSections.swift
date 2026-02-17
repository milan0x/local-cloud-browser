import SwiftUI

struct FavoriteRegionSections<Item: Identifiable & Equatable, RowContent: View>: View {
    @ObservedObject var loader: FavoriteRegionLoader<Item>
    @EnvironmentObject private var favoriteStore: FavoriteRegionStore
    let currentRegion: String
    let selectBy: KeyPath<Item, String>
    @ViewBuilder let rowContent: (Item) -> RowContent

    var body: some View {
        let favorites = favoriteStore.regions.filter { $0 != currentRegion }

        ForEach(favorites, id: \.self) { region in
            favoriteSection(for: region)
        }
    }

    @ViewBuilder
    private func favoriteSection(for region: String) -> some View {
        let state = loader.states[region] ?? FavoriteRegionLoader<Item>.RegionState()

        HStack(spacing: 4) {
            Image(systemName: state.isExpanded ? "chevron.down" : "chevron.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 10)

            Text(regionLabel(region))
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            if state.isExpanded && !state.items.isEmpty {
                Text("\(state.items.count)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if state.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                favoriteStore.remove(region)
            } label: {
                Image(systemName: "star.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove \(region) from favorites")
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            loader.toggleExpanded(region)
        }

        if state.isExpanded {
            if let error = state.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if state.items.isEmpty && !state.isLoading {
                Text("No resources")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(state.items) { item in
                    rowContent(item)
                        .opacity(0.7)
                        .contentShape(Rectangle())
                        .onTapGesture { loader.switchRegion(to: region, selecting: item[keyPath: selectBy]) }
                }
            }
        }
    }

    private func regionLabel(_ code: String) -> String {
        if let region = AWSRegion.find(code) {
            return "\(code) — \(region.displayName)"
        }
        return code
    }
}
