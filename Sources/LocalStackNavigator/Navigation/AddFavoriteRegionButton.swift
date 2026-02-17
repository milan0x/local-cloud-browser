import SwiftUI

struct AddFavoriteRegionButton: View {
    @EnvironmentObject private var favoriteStore: FavoriteRegionStore
    let currentRegion: String

    @State private var showSheet = false

    var body: some View {
        Divider()

        Button {
            showSheet = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "star")
                    .font(.caption)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Add favorite region")
                        .font(.subheadline)
                    if favoriteStore.regions.isEmpty {
                        Text("Watch multiple regions at a time")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSheet) {
            FavoriteRegionSheet(currentRegion: currentRegion)
        }
    }
}

private struct FavoriteRegionSheet: View {
    @EnvironmentObject private var favoriteStore: FavoriteRegionStore
    @Environment(\.dismiss) private var dismiss
    let currentRegion: String

    @State private var search = ""

    private var filteredRegions: [AWSRegion] {
        let available = AWSRegion.allRegions.filter { $0.code != currentRegion }
        guard !search.isEmpty else { return available }
        let query = search.lowercased()
        return available.filter {
            $0.code.lowercased().contains(query) || $0.displayName.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Favorite Regions")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            SearchBarView(query: $search, placeholder: "Filter regions")
                .padding(.horizontal)
                .padding(.bottom, 8)

            List(filteredRegions, id: \.code) { region in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(region.code)
                            .fontWeight(.medium)
                        Text(region.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if favoriteStore.isFavorite(region.code) {
                        Button {
                            favoriteStore.remove(region.code)
                        } label: {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            favoriteStore.add(region.code)
                        } label: {
                            Image(systemName: "star")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(width: 400, height: 450)
    }
}
