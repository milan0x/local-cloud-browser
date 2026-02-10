import SwiftUI

struct AutoRefreshMenuView: View {
    @Binding var interval: Int
    var onRefreshNow: (() -> Void)?

    private static let options: [(label: String, value: Int)] = [
        ("Off", 0),
        ("1 second", 1),
        ("3 seconds", 3),
        ("5 seconds", 5),
        ("10 seconds", 10),
        ("30 seconds", 30),
        ("60 seconds", 60),
    ]

    var body: some View {
        Menu {
            if let onRefreshNow {
                Button {
                    onRefreshNow()
                } label: {
                    Label("Refresh Now", systemImage: "arrow.clockwise")
                }

                Divider()
            }

            ForEach(Self.options, id: \.value) { option in
                Button {
                    interval = option.value
                } label: {
                    if interval == option.value {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.clockwise")
                .foregroundStyle(interval > 0 ? Color.accentColor : .secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(interval > 0 ? "Auto-refresh: \(interval)s" : "Refresh")
    }
}
