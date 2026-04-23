import SwiftUI
import AppKit

/// Standalone permission builder sheet, reachable from the main toolbar.
/// Available proactively so users can configure IAM policies without waiting
/// for something to fail. Shows Full access, Read-only, and Custom permissions
/// for the selected service, with "Granted" badges where detection succeeds.
struct PermissionBuilderSheet: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var client: CloudClient
    @Environment(\.dismiss) private var dismiss

    @State private var selectedServiceKey: String = "s3"
    @State private var selectedCategories: Set<String> = []
    @State private var customPolicyName: String = "LCB-Custom"
    @State private var copiedKey: String?

    @State private var grantedActions: Set<String> = []
    @State private var isDetecting = false
    @State private var detectionSucceeded = false

    @State private var showCustomPermissions = false

    private var categories: [PermissionCategory] {
        ServiceActionCategories.categories(for: selectedServiceKey)
    }

    private var recipe: ServicePermissionRecipe? {
        ServicePermissionRecipe.forService(selectedServiceKey)
    }

    private var username: String? {
        guard let arn = appState.callerIdentity?.arn else { return nil }
        return PermissionHelperView.parseUsername(from: arn)
    }

    // Read-only category IDs per service. These define which categories count
    // toward the "Read-only granted" badge on the Read-only card.
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

    private func isGranted(_ category: PermissionCategory) -> Bool {
        guard detectionSucceeded else { return false }
        return category.actions.allSatisfy { grantedActions.contains($0) }
    }

    private var fullAccessGranted: Bool {
        detectionSucceeded && !categories.isEmpty && categories.allSatisfy { isGranted($0) }
    }

    private var readOnlyGranted: Bool {
        guard detectionSucceeded,
              let readIds = Self.readOnlyCategoryIds[selectedServiceKey] else { return false }
        let readCategories = categories.filter { readIds.contains($0.id) }
        guard !readCategories.isEmpty else { return false }
        return readCategories.allSatisfy { isGranted($0) }
    }

    private static let availableServices: [(key: String, name: String)] = [
        ("s3", "S3"),
        ("iam", "IAM"),
        ("sqs", "SQS"),
        ("sns", "SNS"),
        ("dynamodb", "DynamoDB"),
        ("secretsmanager", "Secrets Manager"),
        ("ssm", "SSM Parameter Store"),
        ("monitoring", "CloudWatch"),
        ("logs", "CloudWatch Logs"),
        ("events", "EventBridge"),
        ("kms", "KMS"),
        ("kinesis", "Kinesis"),
        ("firehose", "Kinesis Firehose"),
        ("states", "Step Functions"),
        ("acm", "ACM"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 720, height: 720)
        .task { await detectPermissions() }
        .onChange(of: selectedServiceKey) {
            selectedCategories.removeAll()
            grantedActions.removeAll()
            detectionSucceeded = false
            Task { await detectPermissions() }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "key.horizontal.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Manage permissions")
                    .font(.title3).bold()
                Text("Grant access for your AWS user.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isDetecting {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let user = username {
                    userChip(user)
                } else {
                    unknownIdentityMessage
                }
                servicePicker

                if let recipe, recipe.fullAccess != nil {
                    fullAccessCard(recipe: recipe)
                }
                readOnlyCard
                if !categories.isEmpty {
                    customPermissionsDisclosure
                }
            }
            .padding(24)
        }
    }

    private var customPermissionsDisclosure: some View {
        clickableDisclosure(
            title: "Custom permissions",
            isExpanded: $showCustomPermissions
        ) {
            customizerCard
                .padding(.top, 8)
        }
    }

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

    private var footer: some View {
        HStack {
            Spacer()
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private func userChip(_ user: String) -> some View {
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
        .background(Capsule().fill(Color.secondary.opacity(0.1)))
    }

    private var unknownIdentityMessage: some View {
        HStack(spacing: 6) {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.orange)
            Text("Unable to identify current user — commands will use YOUR_USER_NAME as a placeholder.")
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }

    private var servicePicker: some View {
        HStack(spacing: 12) {
            Text("Service")
                .font(.callout)
                .foregroundStyle(.secondary)
            Picker("", selection: $selectedServiceKey) {
                ForEach(Self.availableServices, id: \.key) { svc in
                    Text(svc.name).tag(svc.key)
                }
            }
            .labelsHidden()
            Spacer()
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

            if let grant = recipe.fullAccess {
                let user = username ?? "YOUR_USER_NAME"
                commandBlock(command: grant.attachCommand(username: user), copyKey: "full")
            }
        }
    }

    private var readOnlyCard: some View {
        tierCard {
            HStack(spacing: 8) {
                Image(systemName: "eye")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text("Read-only for \(recipe?.displayName ?? selectedServiceKey)")
                    .font(.headline)
                Spacer()
                if readOnlyGranted { grantedBadge }
            }

            Text("Browse and read only — no create, write, update, or delete.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if let grant = recipe?.readOnly {
                let user = username ?? "YOUR_USER_NAME"
                commandBlock(command: grant.attachCommand(username: user), copyKey: "read-only")
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

            Text("Pick exactly which actions to grant. The command updates as you toggle.")
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

            let user = username ?? "YOUR_USER_NAME"
            let command = CustomPolicyBuilder.putUserPolicyCommand(
                username: user,
                policyName: customPolicyName,
                selected: selectedCategories,
                categories: categories
            )
            commandBlock(command: command, copyKey: "custom")
        }
    }

    // MARK: - Primitives

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

    private func copy(_ text: String, key: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        copiedKey = key
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copiedKey == key { copiedKey = nil }
        }
    }

    // MARK: - Detection

    private func detectPermissions() async {
        guard let arn = appState.callerIdentity?.arn else { return }
        let allActions = Array(Set(categories.flatMap(\.actions)))
        guard !allActions.isEmpty else { return }
        isDetecting = true
        defer { isDetecting = false }
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
}
