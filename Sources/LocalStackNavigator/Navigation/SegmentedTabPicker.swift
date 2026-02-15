import SwiftUI

/// A segmented picker for switching between tab cases.
///
/// Generic over any `CaseIterable + Hashable + RawRepresentable<String>` enum.
/// Replaces the repeated Picker+segmented+padding pattern across module views.
struct SegmentedTabPicker<T: CaseIterable & Hashable & RawRepresentable>: View where T.RawValue == String, T.AllCases: RandomAccessCollection {
    @Binding var selection: T
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat

    init(selection: Binding<T>, horizontalPadding: CGFloat = 8, verticalPadding: CGFloat = 6) {
        self._selection = selection
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
    }

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(T.allCases, id: \.self) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
    }
}
