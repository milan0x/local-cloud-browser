import SwiftUI

struct AWSRegionPicker: View {
    @Binding var regionCode: String

    var body: some View {
        Menu {
            ForEach(AWSRegion.allRegions, id: \.code) { region in
                Button {
                    regionCode = region.code
                } label: {
                    Text("\(region.code) — \(region.displayName)")
                }
            }
        } label: {
            Text(regionCode)
        }
    }
}
