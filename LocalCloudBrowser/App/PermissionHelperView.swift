import SwiftUI
import AppKit

struct PermissionHelperView: View {
    @EnvironmentObject private var appState: AppState

    let prompt: PermissionDeniedPrompt

    @State private var showOtherOptions = false
    @State private var showRawError = false
    @State private var copiedKey: String?

    private var recipe: ServicePermissionRecipe? {
        ServicePermissionRecipe.forService(prompt.serviceKey)
    }

    private var username: String? {
        guard let arn = appState.callerIdentity?.arn else { return nil }
        return Self.parseUsername(from: arn)
    }

    private var isAssumedRole: Bool {
        (appState.callerIdentity?.arn ?? "").contains(":assumed-role/")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if prompt.isPermissionsBoundary {
                    boundaryCard
                } else if isAssumedRole {
                    assumedRoleCard
                } else if username == nil {
                    unknownIdentityCard
                } else {
                    recommendedCard
                    if let recipe, recipe.fullAccess != nil {
                        fullAccessCard(recipe: recipe)
                    }
                    otherOptionsDisclosure
                }

                rawErrorDisclosure
                footerActions
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Permission denied")
                        .font(.title3).bold()
                    if let action = prompt.deniedAction {
                        Text(action)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.secondary)
                    } else if let recipe {
                        Text("This identity lacks access to \(recipe.displayName).")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Dismiss") {
                    appState.dismissPermissionPrompt(forService: prompt.serviceKey)
                }
                .buttonStyle(.borderless)
                .help("Hide this panel. It'll come back if the next request is also denied.")
            }

            if let user = username {
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle")
                        .foregroundStyle(.secondary)
                    Text("Current user")
                        .foregroundStyle(.secondary)
                    Text(user)
                        .font(.system(.body, design: .monospaced))
                }
                .font(.callout)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.secondary.opacity(0.1))
                )
            }
        }
    }

    // MARK: - Cards

    private var recommendedCard: some View {
        tierCard(accent: .accentColor) {
            HStack(spacing: 8) {
                Image(systemName: "star.fill")
                    .foregroundStyle(Color.accentColor)
                    .font(.caption)
                Text("Recommended — read-only for \(recipe?.displayName ?? "this service")")
                    .font(.headline)
                Spacer()
                badge("Fewest permissions needed", color: .accentColor)
            }

            Text("Grants read access across the whole service so browsing views all work.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if let recipe, let grant = recipe.readOnly, let user = username {
                commandBlock(
                    command: grant.attachCommand(username: user),
                    copyKey: "read-only"
                )
            } else {
                Text("No read-only grant is needed — this service is always available to authenticated callers.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func fullAccessCard(recipe: ServicePermissionRecipe) -> some View {
        tierCard(accent: nil) {
            HStack(spacing: 8) {
                Image(systemName: "pencil.and.outline")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text("Full access for \(recipe.displayName)")
                    .font(.headline)
                Spacer()
            }

            Text("Also allows create, update, and delete — pick this if you want to manage resources, not just browse them.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if let grant = recipe.fullAccess, let user = username {
                commandBlock(
                    command: grant.attachCommand(username: user),
                    copyKey: "full"
                )
            }
        }
    }

    private var otherOptionsDisclosure: some View {
        clickableDisclosure(
            title: "Other options",
            isExpanded: $showOtherOptions
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if let action = prompt.deniedAction, let user = username {
                    minimalCard(action: action, user: user)
                }
                adminCard
            }
            .padding(.top, 8)
        }
    }

    private func minimalCard(action: String, user: String) -> some View {
        tierCard(accent: nil) {
            HStack(spacing: 8) {
                Image(systemName: "scope")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text("Minimal — only \(action)")
                    .font(.headline)
                Spacer()
            }

            Text("Strictly the one action that failed. You may hit more permission errors on related actions in the same module.")
                .font(.callout)
                .foregroundStyle(.secondary)

            commandBlock(
                command: minimalCommand(action: action, user: user),
                copyKey: "minimal"
            )
        }
    }

    private var adminCard: some View {
        tierCard(accent: .orange) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Text("Full account administrator")
                    .font(.headline)
                Spacer()
            }

            Text("Grants every AWS permission across every service. Convenient, but the blast radius of leaked credentials is the entire account.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if let user = username {
                commandBlock(
                    command: ServicePermissionRecipe.administratorAccess.attachCommand(username: user),
                    copyKey: "admin"
                )
            }
        }
    }

    private var boundaryCard: some View {
        tierCard(accent: .orange) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Text("A permissions boundary is blocking access")
                    .font(.headline)
                Spacer()
            }

            Text("Your user has a permissions boundary that caps what any attached policy can do. Adding a new policy won't help — the boundary has to be removed or widened first.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if let user = username {
                commandBlock(
                    command: """
                    aws iam delete-user-permissions-boundary \\
                      --user-name \(user)
                    """,
                    copyKey: "delete-boundary"
                )
                Text("If removing the boundary isn't an option, edit the boundary policy JSON in the AWS Console to include the denied action.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var assumedRoleCard: some View {
        tierCard(accent: nil) {
            HStack(spacing: 8) {
                Image(systemName: "person.2.badge.gearshape")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text("You're using an assumed role")
                    .font(.headline)
                Spacer()
            }

            Text("Role sessions can't have policies attached directly. Add the permission to the underlying IAM role in the AWS Console, or connect with a different user.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if let arn = appState.callerIdentity?.arn {
                Text(arn)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(codeBackground)
            }
        }
    }

    private var unknownIdentityCard: some View {
        tierCard(accent: nil) {
            HStack(spacing: 8) {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text("Unable to identify current user")
                    .font(.headline)
                Spacer()
            }

            Text("The app couldn't determine your AWS identity. Replace `YOUR_USER_NAME` with your own IAM user below.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if let grant = recipe?.readOnly {
                commandBlock(
                    command: grant.attachCommand(username: "YOUR_USER_NAME"),
                    copyKey: "unknown-user"
                )
            }
        }
    }

    // MARK: - Raw error + footer

    private var rawErrorDisclosure: some View {
        clickableDisclosure(
            title: "Full AWS error message",
            isExpanded: $showRawError
        ) {
            Text(prompt.rawMessage)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(codeBackground)
                .padding(.top, 8)
        }
    }

    private var footerActions: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("After you've run the command in your terminal:")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                appState.autoRefresh.triggerNow()
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .help("Re-send the request that was denied. If permissions now work, this panel dismisses automatically.")
        }
        .padding(.top, 4)
    }

    // MARK: - Primitives

    private func tierCard<Content: View>(
        accent: Color?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(accent?.opacity(0.45) ?? Color.secondary.opacity(0.18),
                        lineWidth: accent == nil ? 1 : 1.5)
        )
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(color.opacity(0.12))
            )
    }

    private func commandBlock(command: String, copyKey: String) -> some View {
        ZStack(alignment: .topTrailing) {
            Text(command)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .padding(.trailing, 44) // leave room for copy button
                .background(codeBackground)

            Button {
                copy(command, key: copyKey)
            } label: {
                Image(systemName: copiedKey == copyKey ? "checkmark" : "doc.on.doc")
                    .font(.body)
                    .foregroundStyle(copiedKey == copyKey ? Color.green : Color.secondary)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.9))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.secondary.opacity(0.2))
                    )
            }
            .buttonStyle(.plain)
            .padding(6)
            .help(copiedKey == copyKey ? "Copied" : "Copy command")
        }
    }

    private var codeBackground: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color(nsColor: .textBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.2))
            )
    }

    /// DisclosureGroup replacement where the entire header row toggles the state
    /// (SwiftUI's built-in DisclosureGroup only responds to the chevron on macOS).
    private func clickableDisclosure<Content: View>(
        title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .contentShape(Rectangle())
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                content()
            }
        }
    }

    // MARK: - Helpers

    private func copy(_ text: String, key: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        copiedKey = key
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copiedKey == key { copiedKey = nil }
        }
    }

    private func minimalCommand(action: String, user: String) -> String {
        let sanitized = action.replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "*", with: "Star")
        let policyName = "LCB-Minimal-\(sanitized)"
        let document = """
            {"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"\(action)","Resource":"*"}]}
            """
        return """
            aws iam put-user-policy \\
              --user-name \(user) \\
              --policy-name \(policyName) \\
              --policy-document '\(document)'
            """
    }

    /// Extracts the IAM user name from an ARN like
    /// `arn:aws:iam::123:user/path/to/alice` → `alice`.
    /// Returns nil for non-user ARNs (assumed-role, federated-user).
    static func parseUsername(from arn: String) -> String? {
        guard arn.contains(":user/") else { return nil }
        guard let range = arn.range(of: ":user/") else { return nil }
        let afterPrefix = arn[range.upperBound...]
        return afterPrefix.components(separatedBy: "/").last
    }
}
