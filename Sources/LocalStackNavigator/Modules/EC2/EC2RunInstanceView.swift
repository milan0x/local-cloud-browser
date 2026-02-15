import SwiftUI

struct EC2RunInstanceView: View {
    @ObservedObject var service: EC2Service
    @Environment(\.dismiss) private var dismiss
    let keyPairs: [EC2KeyPair]
    let securityGroups: [EC2SecurityGroup]

    @State private var imageId = "ami-ff0fea8310f3"
    @State private var instanceType = "t2.micro"
    @State private var selectedKeyPair = ""
    @State private var selectedSecurityGroupIds: Set<String> = []
    @State private var count = 1
    @State private var serviceError: ServiceError?
    @State private var isSaving = false
    @State private var hasAttemptedCreate = false

    private static let instanceTypes = [
        "t2.nano", "t2.micro", "t2.small", "t2.medium", "t2.large",
        "t3.nano", "t3.micro", "t3.small", "t3.medium", "t3.large",
        "m5.large", "m5.xlarge", "c5.large", "c5.xlarge",
        "r5.large", "r5.xlarge",
    ]

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Instance Configuration") {
                    TextField("AMI ID", text: $imageId)
                    Picker("Instance Type", selection: $instanceType) {
                        ForEach(Self.instanceTypes, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }
                    Stepper(value: $count, in: 1...10) {
                        HStack {
                            Text("Count")
                            Spacer()
                            Text("\(count)")
                                .monospacedDigit()
                        }
                    }
                }

                Section("Key Pair") {
                    Picker("Key Pair", selection: $selectedKeyPair) {
                        Text("None").tag("")
                        ForEach(keyPairs) { kp in
                            Text(kp.keyName).tag(kp.keyName)
                        }
                    }
                }

                Section("Security Groups") {
                    if securityGroups.isEmpty {
                        Text("No security groups available")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(securityGroups) { sg in
                            Toggle(isOn: Binding(
                                get: { selectedSecurityGroupIds.contains(sg.groupId) },
                                set: { isOn in
                                    if isOn {
                                        selectedSecurityGroupIds.insert(sg.groupId)
                                    } else {
                                        selectedSecurityGroupIds.remove(sg.groupId)
                                    }
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(sg.groupName)
                                    Text(sg.groupId)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            if hasAttemptedCreate && imageId.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("AMI ID is required")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Launch") { launch() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid || isSaving)
            }
            .padding()
        }
        .frame(width: 460, height: 480)
        .serviceErrorAlert(error: $serviceError)
    }

    private var trimmedImageId: String {
        imageId.trimmingCharacters(in: .whitespaces)
    }

    private var isValid: Bool {
        !trimmedImageId.isEmpty
    }

    private func launch() {
        hasAttemptedCreate = true
        guard isValid else { return }
        isSaving = true
        serviceError = nil
        Task {
            do {
                try await service.runInstance(
                    imageId: trimmedImageId,
                    instanceType: instanceType,
                    keyName: selectedKeyPair.isEmpty ? nil : selectedKeyPair,
                    securityGroupIds: Array(selectedSecurityGroupIds),
                    count: count
                )
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
