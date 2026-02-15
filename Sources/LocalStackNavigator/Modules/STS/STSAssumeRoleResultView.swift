import SwiftUI
import AppKit

struct STSAssumeRoleResultView: View {
    let credentials: AssumedRoleCredentials
    let onClear: () -> Void

    @State private var showSecretKey = false
    @State private var showSessionToken = false

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                labeledRow("Access Key ID") {
                    CopyableValue(text: credentials.accessKeyId, monospaced: true)
                }

                labeledRow("Secret Access Key") {
                    HStack(spacing: 6) {
                        if showSecretKey {
                            CopyableValue(text: credentials.secretAccessKey, monospaced: true)
                        } else {
                            Text(String(repeating: "\u{2022}", count: 20))
                                .font(.body.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            showSecretKey.toggle()
                        } label: {
                            Image(systemName: showSecretKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                        if !showSecretKey {
                            CopyButton(text: credentials.secretAccessKey)
                        }
                    }
                }

                labeledRow("Session Token") {
                    HStack(spacing: 6) {
                        if showSessionToken {
                            CopyableValue(text: credentials.sessionToken, font: .caption, monospaced: true)
                        } else {
                            Text(String(repeating: "\u{2022}", count: 20))
                                .font(.body.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            showSessionToken.toggle()
                        } label: {
                            Image(systemName: showSessionToken ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                        if !showSessionToken {
                            CopyButton(text: credentials.sessionToken)
                        }
                    }
                }

                if !credentials.expiration.isEmpty {
                    labeledRow("Expiration") {
                        Text(credentials.expiration)
                            .foregroundStyle(.secondary)
                    }
                }

                if !credentials.assumedRoleArn.isEmpty {
                    labeledRow("Role ARN") {
                        CopyableValue(text: credentials.assumedRoleArn, font: .caption, monospaced: true)
                    }
                }

                if !credentials.assumedRoleId.isEmpty {
                    labeledRow("Role ID") {
                        CopyableValue(text: credentials.assumedRoleId, monospaced: true)
                    }
                }

                HStack {
                    Spacer()
                    Button("Clear") { onClear() }
                        .buttonStyle(.borderless)
                }
            }
            .padding(4)
        } label: {
            HStack(spacing: 6) {
                Text("Assumed Role Credentials")
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    private func labeledRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .trailing)
            content()
        }
    }
}
