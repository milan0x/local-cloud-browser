import SwiftUI

enum EC2RuleDirection: String {
    case inbound = "Inbound"
    case outbound = "Outbound"
}

struct EC2AddRuleView: View {
    @ObservedObject var service: EC2Service
    @Environment(\.dismiss) private var dismiss
    let groupId: String
    let direction: EC2RuleDirection

    @State private var protocolType = "tcp"
    @State private var fromPort = "80"
    @State private var toPort = "80"
    @State private var cidrIp = "0.0.0.0/0"
    @State private var ruleDescription = ""
    @State private var serviceError: ServiceError?
    @State private var isSaving = false
    @State private var hasAttemptedCreate = false

    private static let protocols = [
        ("tcp", "TCP"),
        ("udp", "UDP"),
        ("icmp", "ICMP"),
        ("-1", "All Traffic"),
    ]

    private var needsPortRange: Bool {
        protocolType != "-1" && protocolType != "icmp"
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Picker("Protocol", selection: $protocolType) {
                    ForEach(Self.protocols, id: \.0) { proto in
                        Text(proto.1).tag(proto.0)
                    }
                }

                if needsPortRange {
                    TextField("From Port", text: $fromPort)
                    TextField("To Port", text: $toPort)
                }

                TextField(direction == .inbound ? "Source CIDR" : "Destination CIDR", text: $cidrIp)
                TextField("Description (optional)", text: $ruleDescription)
            }
            .formStyle(.grouped)

            if hasAttemptedCreate && !isValid {
                VStack(alignment: .leading, spacing: 4) {
                    if cidrIp.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("CIDR is required")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                    if needsPortRange && !portsValid {
                        Text("Invalid port range")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
                .padding(.horizontal)
            }

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add \(direction.rawValue) Rule") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid || isSaving)
            }
            .padding()
        }
        .frame(width: 400)
        .frame(minHeight: 300)
        .serviceErrorAlert(error: $serviceError)
    }

    private var portsValid: Bool {
        if !needsPortRange { return true }
        guard let from = Int(fromPort.trimmingCharacters(in: .whitespaces)),
              let to = Int(toPort.trimmingCharacters(in: .whitespaces)),
              from >= 0, from <= 65535, to >= 0, to <= 65535, from <= to else {
            return false
        }
        return true
    }

    private var isValid: Bool {
        let trimmedCidr = cidrIp.trimmingCharacters(in: .whitespaces)
        return !trimmedCidr.isEmpty && portsValid
    }

    private func save() {
        hasAttemptedCreate = true
        guard isValid else { return }
        isSaving = true
        serviceError = nil

        let from = needsPortRange ? Int(fromPort.trimmingCharacters(in: .whitespaces)) : nil
        let to = needsPortRange ? Int(toPort.trimmingCharacters(in: .whitespaces)) : nil
        let trimmedCidr = cidrIp.trimmingCharacters(in: .whitespaces)
        let desc = ruleDescription.trimmingCharacters(in: .whitespaces)

        Task {
            do {
                switch direction {
                case .inbound:
                    try await service.authorizeSecurityGroupIngress(
                        groupId: groupId,
                        ipProtocol: protocolType,
                        fromPort: from,
                        toPort: to,
                        cidrIp: trimmedCidr,
                        description: desc.isEmpty ? nil : desc
                    )
                case .outbound:
                    try await service.authorizeSecurityGroupEgress(
                        groupId: groupId,
                        ipProtocol: protocolType,
                        fromPort: from,
                        toPort: to,
                        cidrIp: trimmedCidr,
                        description: desc.isEmpty ? nil : desc
                    )
                }
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
