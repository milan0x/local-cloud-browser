import SwiftUI

struct AWSRegionPicker: View {
    @Binding var regionCode: String

    private static let items: [SearchableDropdownItem] = AWSRegion.allRegions.map {
        SearchableDropdownItem(id: $0.code, label: $0.code, description: $0.displayName)
    }

    var body: some View {
        SearchableDropdown(
            items: Self.items,
            selectedID: $regionCode,
            placeholder: "Select region..."
        )
    }
}
