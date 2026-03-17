import SwiftUI

struct Route53CreateRecordView: View {
    @ObservedObject var service: Route53Service
    let zoneId: String
    let zoneName: String
    @Environment(\.dismiss) private var dismiss
    @State private var recordName = ""
    @State private var recordType = "A"
    @State private var ttl = "300"
    @State private var valuesText = ""
    @State private var serviceError: ServiceError?
    @State private var isSaving = false

    var body: some View {
        CreateFormScaffold(
            width: 450,
            isValid: isValid,
            isCreating: isSaving,
            serviceError: $serviceError,
            onCreate: save
        ) {
                TextField("Record Name", text: $recordName)
                    .help("e.g. www or subdomain.example.com")

                Picker("Type", selection: $recordType) {
                    ForEach(route53RecordTypes, id: \.self) { type in
                        Text(type).tag(type)
                    }
                }

                TextField("TTL (seconds)", text: $ttl)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Values (one per line)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $valuesText)
                        .font(.body.monospaced())
                        .frame(minHeight: 80)
                        .border(Color.secondary.opacity(0.3))
                }

                Text(valueHint)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
        }
    }

    private var valueHint: String {
        switch recordType {
        case "A": "IP address, e.g. 1.2.3.4"
        case "AAAA": "IPv6 address, e.g. 2001:db8::1"
        case "CNAME": "Domain name, e.g. other.example.com"
        case "MX": "Priority + domain, e.g. 10 mail.example.com"
        case "TXT": "Text value, e.g. \"v=spf1 include:_spf.google.com ~all\""
        case "NS": "Nameserver, e.g. ns1.example.com"
        case "SRV": "Priority Weight Port Target, e.g. 10 5 443 server.example.com"
        case "CAA": "Flag Tag Value, e.g. 0 issue \"letsencrypt.org\""
        default: "Enter values, one per line"
        }
    }

    private var isValid: Bool {
        !recordName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !valuesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (Int(ttl) ?? 0) > 0
    }

    private var parsedValues: [String] {
        valuesText
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func save() {
        isSaving = true
        serviceError = nil

        // Normalize the record name — append zone name if bare subdomain
        var name = recordName.trimmingCharacters(in: .whitespaces)
        if !name.contains(".") {
            name = "\(name).\(zoneName)"
        }
        if !name.hasSuffix(".") {
            name += "."
        }

        Task {
            do {
                try await service.createRecordSet(
                    zoneId: zoneId,
                    name: name,
                    type: recordType,
                    ttl: Int(ttl) ?? 300,
                    values: parsedValues
                )
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
