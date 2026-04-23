import SwiftUI
import AppKit

struct PermissionHelperView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var client: CloudClient

    let prompt: PermissionDeniedPrompt

    @State private var showCustomPermissions = false
    @State private var showRawError = false
    @State private var copiedKey: String?

    @State private var selectedCategories: Set<String> = []
    @State private var customPolicyName: String = "LCB-Custom"

    @State private var grantedActions: Set<String> = []
    @State private var detectionSucceeded = false

    @State private var denyingInlinePolicies: [String] = []
    @State private var showTroubleshoot = false

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

    private var categories: [PermissionCategory] {
        ServiceActionCategories.categories(for: prompt.serviceKey)
    }

    private var headerText: String {
        guard let action = prompt.deniedAction else { return "Permission denied" }
        return DeniedActionKind.classify(action).headerText
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
                    if !denyingInlinePolicies.isEmpty, let user = username {
                        detectedDeniesCard(user: user)
                    }
                    if let recipe, recipe.fullAccess != nil {
                        fullAccessCard(recipe: recipe)
                    }
                    readOnlyCard
                    customPermissionsDisclosure
                    troubleshootDisclosure
                }

                rawErrorDisclosure
                footerActions
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onAppear { preselectDeniedCategory() }
        .task { await detectPermissions() }
        .onChange(of: appState.callerIdentity?.arn) {
            Task { await detectPermissions() }
        }
    }

    private func isGranted(_ category: PermissionCategory) -> Bool {
        guard detectionSucceeded else { return false }
        return category.actions.allSatisfy { grantedActions.contains($0) }
    }

    private var fullAccessGranted: Bool {
        detectionSucceeded && !categories.isEmpty && categories.allSatisfy { isGranted($0) }
    }

    private var readOnlyGranted: Bool {
        guard detectionSucceeded,
              let readIds = Self.readOnlyCategoryIds[prompt.serviceKey] else { return false }
        let readCategories = categories.filter { readIds.contains($0.id) }
        guard !readCategories.isEmpty else { return false }
        return readCategories.allSatisfy { isGranted($0) }
    }

    private static let readOnlyCategoryIds: [String: Set<String>] = [
        "s3": ["list-buckets", "browse-objects", "download"],
        "iam": ["view-users", "view-roles", "view-policies", "view-groups"],
        "sqs": ["view", "receive"],
        "sns": ["view"],
        "dynamodb": ["view", "read"],
        "secretsmanager": ["view", "read-values"],
        "ssm": ["view", "read"],
        "monitoring": ["view-metrics", "view-alarms"],
        "logs": ["view", "read"],
        "events": ["view"],
        "kms": ["view"],
        "kinesis": ["view", "read"],
        "firehose": ["view"],
        "states": ["view"],
        "acm": ["view"],
    ]

    private var grantedBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.green)
                .font(.caption2)
            Text("Granted")
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.green)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.green.opacity(0.12)))
    }

    private func detectPermissions() async {
        guard let arn = appState.callerIdentity?.arn else { return }
        let allActions = Array(Set(categories.flatMap(\.actions)))
        if !allActions.isEmpty {
            do {
                let allowed = try await client.simulatePrincipalPolicy(
                    principal: arn,
                    actions: allActions
                )
                grantedActions = allowed
                detectionSucceeded = true
            } catch {
                detectionSucceeded = false
                Log.warn("Permission detection failed: \(error.localizedDescription)", category: "App")
            }
        }

        // Also detect inline policies that explicitly deny this service.
        if let user = username {
            denyingInlinePolicies = await client.findInlineDeniesForService(
                userName: user,
                servicePrefix: prompt.serviceKey
            )
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
                    Text(headerText)
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

    private func fullAccessCard(recipe: ServicePermissionRecipe) -> some View {
        tierCard {
            HStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text("Full access for \(recipe.displayName)")
                    .font(.headline)
                Spacer()
                if fullAccessGranted { grantedBadge }
            }

            Text("Read, write, delete, and manage resources — pick this if you want to do everything the app offers.")
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

    private var readOnlyCard: some View {
        tierCard {
            HStack(spacing: 8) {
                Image(systemName: "eye")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text("Read-only for \(recipe?.displayName ?? "this service")")
                    .font(.headline)
                Spacer()
                if readOnlyGranted { grantedBadge }
            }

            Text("Browse and read only — no create, write, update, or delete.")
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

    private var customizerCard: some View {
        tierCard {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text("Custom permissions")
                    .font(.headline)
                Spacer()
            }

            Text("Pick exactly which actions to grant. The command below updates as you toggle.")
                .font(.callout)
                .foregroundStyle(.secondary)

            let columns = [GridItem(.flexible(), alignment: .leading),
                           GridItem(.flexible(), alignment: .leading)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(categories) { category in
                    HStack(spacing: 6) {
                        Toggle(isOn: Binding(
                            get: { selectedCategories.contains(category.id) },
                            set: { isOn in
                                if isOn { selectedCategories.insert(category.id) }
                                else { selectedCategories.remove(category.id) }
                            }
                        )) {
                            Text(category.displayName)
                                .font(.callout)
                        }
                        .toggleStyle(.checkbox)

                        if isGranted(category) { grantedBadge }
                    }
                }
            }
            .padding(.vertical, 4)

            if let user = username {
                let command = CustomPolicyBuilder.putUserPolicyCommand(
                    username: user,
                    policyName: customPolicyName,
                    selected: selectedCategories,
                    categories: categories
                )
                commandBlock(command: command, copyKey: "custom")
            }
        }
    }

    private var troubleshootDisclosure: some View {
        clickableDisclosure(
            title: "Still blocked? Troubleshoot restrictions",
            isExpanded: $showTroubleshoot
        ) {
            genericTroubleshootCard
                .padding(.top, 8)
        }
    }

    private func detectedDeniesCard(user: String) -> some View {
        tierCard(accent: .orange) {
            HStack(spacing: 8) {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Text("Inline policies blocking this service")
                    .font(.headline)
                Spacer()
            }

            Text("These inline policies on `\(user)` contain explicit Deny statements that block access. Explicit Deny in IAM beats every Allow — removing them is the fix.")
                .font(.callout)
                .foregroundStyle(.secondary)

            ForEach(denyingInlinePolicies, id: \.self) { policyName in
                VStack(alignment: .leading, spacing: 4) {
                    Text(policyName)
                        .font(.system(.callout, design: .monospaced))
                    commandBlock(
                        command: """
                        aws iam delete-user-policy \\
                          --user-name \(user) \\
                          --policy-name \(policyName)
                        """,
                        copyKey: "delete-\(policyName)"
                    )
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.caption)
                Text("IAM changes can take 5–10 seconds to propagate. If Retry doesn't work right away, wait a moment and try again.")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
            .padding(.top, 2)
        }
    }

    private var genericTroubleshootCard: some View {
        tierCard {
            HStack(spacing: 8) {
                Image(systemName: "stethoscope")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text("Diagnose other restrictions")
                    .font(.headline)
                Spacer()
            }

            Text("Run these to find what else might be blocking access — inline policies you don't recognize, permissions boundaries, or service control policies from your AWS Organization.")
                .font(.callout)
                .foregroundStyle(.secondary)

            let user = username ?? "YOUR_USER_NAME"
            commandBlock(
                command: "aws iam list-user-policies --user-name \(user)",
                copyKey: "list-policies"
            )
            commandBlock(
                command: "aws iam get-user --user-name \(user)",
                copyKey: "get-user"
            )
            if let action = prompt.deniedAction, let arn = appState.callerIdentity?.arn {
                commandBlock(
                    command: """
                    aws iam simulate-principal-policy \\
                      --policy-source-arn \(arn) \\
                      --action-names \(action)
                    """,
                    copyKey: "simulate"
                )
            }
        }
    }

    private var customPermissionsDisclosure: some View {
        clickableDisclosure(
            title: "Custom permissions",
            isExpanded: $showCustomPermissions
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if !categories.isEmpty {
                    customizerCard
                } else {
                    Text("No custom categories defined for this service yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.top, 8)
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
        tierCard {
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
        tierCard {
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
            .environment(\.controlActiveState, .active)
            .help("Re-send the request that was denied. If permissions now work, this panel dismisses automatically.")
        }
        .padding(.top, 4)
    }

    // MARK: - Primitives

    private func tierCard<Content: View>(
        accent: Color? = nil,
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

    private func commandBlock(command: String, copyKey: String) -> some View {
        ZStack(alignment: .topTrailing) {
            Text(command)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .padding(.trailing, 44)
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

    /// Pre-checks the category matching the current denied action, if any.
    private func preselectDeniedCategory() {
        guard selectedCategories.isEmpty,
              let action = prompt.deniedAction,
              let category = ServiceActionCategories.matching(action: action, in: categories) else { return }
        selectedCategories.insert(category.id)
    }

    /// Extracts the IAM user name from an ARN like
    /// `arn:aws:iam::123:user/path/to/alice` → `alice`.
    static func parseUsername(from arn: String) -> String? {
        guard arn.contains(":user/") else { return nil }
        guard let range = arn.range(of: ":user/") else { return nil }
        let afterPrefix = arn[range.upperBound...]
        return afterPrefix.components(separatedBy: "/").last
    }
}
