import SwiftUI

/// A borderless icon button with an expanded hit target for use in list headers.
///
/// Replaces the repeated `Button { … } label: { Image(systemName:) } .buttonStyle(.borderless)`
/// pattern found across all module list views. The 28×28 frame ensures the entire
/// visual area is clickable, not just the SF Symbol pixels.
struct ListHeaderButton: View {
    let icon: String
    let color: Color
    let isDisabled: Bool
    let help: String
    let action: () -> Void

    init(_ icon: String, color: Color = .primary, isDisabled: Bool = false, help: String = "", action: @escaping () -> Void) {
        self.icon = icon
        self.color = color
        self.isDisabled = isDisabled
        self.help = help
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .foregroundStyle(isDisabled ? .gray : color)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(isDisabled)
        .help(help)
    }
}
