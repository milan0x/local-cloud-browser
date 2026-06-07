import SwiftUI

struct DonationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var enlargedEntry: DonationEntry?

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Support development")
                            .font(.title2.weight(.semibold))
                        Text("Totally optional. The app is free with full features either way.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 10)

                Divider()

                VStack(spacing: 10) {
                    ForEach(DonationAddress.all) { entry in
                        DonationRow(entry: entry) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                enlargedEntry = entry
                            }
                        }
                    }
                    Divider()
                        .padding(.horizontal, 20)
                        .padding(.vertical, 2)
                    BackupRow()
                }
                .padding(.vertical, 12)
            }

            if let entry = enlargedEntry {
                EnlargedQRView(entry: entry) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        enlargedEntry = nil
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(width: 560, height: 596)
    }
}

private struct DonationRow: View {
    let entry: DonationEntry
    let onTapQR: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            QRThumb(entry: entry, onTap: onTapQR)
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.label)
                    .font(.headline)
                Text(entry.address)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                DonationCopyButton(text: entry.address)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
    }
}

private struct QRThumb: View {
    let entry: DonationEntry
    let onTap: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomTrailing) {
                qrImage
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .padding(4)
                    .opacity(isHovering ? 1 : 0)
            }
            .scaleEffect(isHovering ? 1.04 : 1.0)
            .shadow(color: .black.opacity(isHovering ? 0.18 : 0), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .help("Click to enlarge")
        .accessibilityLabel("\(entry.label) QR code, click to enlarge")
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.18)) { isHovering = hovering }
            if hovering {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }

    @ViewBuilder
    private var qrImage: some View {
        if let qr = QRGenerator.image(from: entry.address, size: 200) {
            Image(nsImage: qr)
                .interpolation(.none)
                .resizable()
                .frame(width: 96, height: 96)
                .padding(4)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
                )
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.quaternary)
                .frame(width: 96, height: 96)
        }
    }
}

private struct EnlargedQRView: View {
    let entry: DonationEntry
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 16) {
                Text(entry.label)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)

                qrImage

                Text(entry.address)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .frame(maxWidth: 360)

                HStack(spacing: 10) {
                    DonationCopyButton(text: entry.address)
                    Button("Close", action: onDismiss)
                        .controlSize(.small)
                        .keyboardShortcut(.cancelAction)
                }
                .padding(.top, 4)
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private var qrImage: some View {
        if let qr = QRGenerator.image(from: entry.address, size: 600) {
            Image(nsImage: qr)
                .interpolation(.none)
                .resizable()
                .frame(width: 320, height: 320)
                .padding(16)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.quaternary)
                .frame(width: 320, height: 320)
        }
    }
}

private struct BackupRow: View {
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("Backup BTC")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(DonationAddress.btcBackup)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            DonationCopyButton(text: DonationAddress.btcBackup)
        }
        .padding(.horizontal, 20)
    }
}

private struct DonationCopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            withAnimation(.easeOut(duration: 0.15)) { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                withAnimation(.easeOut(duration: 0.2)) { copied = false }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                Text(copied ? "Copied" : "Copy")
            }
            .font(.caption)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}
