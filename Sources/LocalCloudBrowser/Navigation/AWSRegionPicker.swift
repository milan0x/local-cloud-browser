import SwiftUI

struct AWSRegionPicker: View {
    @Binding var regionCode: String

    var body: some View {
        Picker(selection: $regionCode) {
            ForEach(AWSRegion.allRegions, id: \.code) { region in
                Text("\(region.code) — \(region.displayName)")
                    .tag(region.code)
            }
        } label: {
            EmptyView()
        }
    }
}
