import SwiftUI
import AppKit

struct CopyableValue: View {
    let text: String
    var font: Font = .body
    var monospaced: Bool = false
    var allowsWrapping: Bool = false

    @State private var isHovered = false
    @State private var showCopied = false

    private var resolvedFont: Font {
        monospaced ? .system(.body, design: .monospaced) : font
    }

    private var isActive: Bool {
        isHovered || showCopied
    }

    var body: some View {
        Button {
            copyToClipboard()
        } label: {
            Text(text)
                .font(resolvedFont)
                .lineLimit(allowsWrapping ? nil : 1)
                .fixedSize(horizontal: false, vertical: allowsWrapping)
                .blur(radius: isActive ? 3 : 0)
                .animation(.easeInOut(duration: 0.2), value: isActive)
                .overlay {
                    if isActive {
                        HStack(spacing: 4) {
                            Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                                .font(.callout)
                            Text(showCopied ? "Copied to Clipboard" : "Copy to Clipboard")
                                .font(.callout)
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(showCopied ? .green : .primary)
                        .animation(.easeInOut(duration: 0.15), value: showCopied)
                        .transition(.opacity.animation(.easeInOut(duration: 0.15)))
                        .allowsHitTesting(false)
                    }
                }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if !showCopied {
                isHovered = hovering
            }
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        withAnimation(.easeInOut(duration: 0.15)) {
            showCopied = true
            isHovered = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeInOut(duration: 0.3)) {
                showCopied = false
            }
        }
    }
}

struct CopyButton: View {
    let text: String

    @State private var showCopied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            withAnimation(.easeInOut(duration: 0.15)) {
                showCopied = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showCopied = false
                }
            }
        } label: {
            ZStack {
                Image(systemName: "doc.on.doc")
                    .opacity(showCopied ? 0 : 1)
                Image(systemName: "checkmark")
                    .opacity(showCopied ? 1 : 0)
            }
            .foregroundStyle(showCopied ? .green : .secondary)
            .animation(.easeInOut(duration: 0.15), value: showCopied)
            .frame(width: 16, height: 16)
        }
        .buttonStyle(.plain)
    }
}
