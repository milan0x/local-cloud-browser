import SwiftUI

struct ConnectionProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let existing: ConnectionProfile?
    let canDelete: Bool
    let onSave: (ConnectionProfile) -> Void
    let onDelete: (() -> Void)?

    @State private var name: String
    @State private var endpoint: String
    @State private var region: String
    @State private var accessKeyId: String
    @State private var secretAccessKey: String
    @State private var healthPath: String
    @State private var s3Domain: String
    @State private var apiGatewayDomain: String
    @State private var testResult: TestResult?
    @State private var isTesting = false
    @State private var showDeleteConfirmation = false
    @State private var showAdvanced = false
    @FocusState private var focusedField: String?

    enum TestResult {
        case success(String)
        case failure(String)
    }

    init(existing: ConnectionProfile? = nil, canDelete: Bool = false, onSave: @escaping (ConnectionProfile) -> Void, onDelete: (() -> Void)? = nil) {
        self.existing = existing
        self.canDelete = canDelete
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: existing?.name ?? "")
        _endpoint = State(initialValue: existing?.endpoint ?? "http://localhost:4566")
        _region = State(initialValue: existing?.region ?? "us-east-1")
        _accessKeyId = State(initialValue: existing?.accessKeyId ?? "test")
        _secretAccessKey = State(initialValue: existing?.secretAccessKey ?? "test")
        _healthPath = State(initialValue: Self.customOrEmpty(existing?.healthPath, default: ConnectionProfile.defaultHealthPath))
        _s3Domain = State(initialValue: Self.customOrEmpty(existing?.s3Domain, default: ConnectionProfile.defaultS3Domain))
        _apiGatewayDomain = State(initialValue: Self.customOrEmpty(existing?.apiGatewayDomain, default: ConnectionProfile.defaultApiGatewayDomain))
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && URL(string: endpoint) != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Name", text: $name)
                    .focused($focusedField, equals: "name")
                TextField("Endpoint", text: $endpoint)
                LabeledContent("Default Region") {
                    AWSRegionPicker(regionCode: $region)
                }
                TextField("Access Key ID", text: $accessKeyId)
                SecureField("Secret Access Key", text: $secretAccessKey)

                DisclosureGroup(isExpanded: $showAdvanced) {
                    TextField("Health Check Path", text: $healthPath, prompt: Text("e.g. health"))
                    TextField("S3 Domain", text: $s3Domain, prompt: Text("e.g. s3.localhost"))
                    TextField("API Gateway Domain", text: $apiGatewayDomain, prompt: Text("e.g. execute-api.localhost"))
                } label: {
                    Text("Advanced")
                        .onTapGesture { showAdvanced.toggle() }
                }

                Section {
                    HStack {
                        Button {
                            testConnection()
                        } label: {
                            HStack(spacing: 6) {
                                if isTesting {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Text(isTesting ? "Testing..." : "Test Connection")
                            }
                        }
                        .disabled(URL(string: endpoint) == nil || isTesting)

                        if let result = testResult {
                            testResultLabel(result)
                        }
                    }
                }

                if existing != nil {
                    Section {
                        if canDelete {
                            Button(role: .destructive) {
                                showDeleteConfirmation = true
                            } label: {
                                Label("Delete Connection", systemImage: "trash")
                            }
                        } else {
                            Label("This is a default profile and cannot be deleted.", systemImage: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(existing == nil ? "Add" : "Save") {
                    let profile = ConnectionProfile(
                        id: existing?.id ?? UUID(),
                        name: name.trimmingCharacters(in: .whitespaces),
                        endpoint: endpoint,
                        region: region,
                        accessKeyId: accessKeyId,
                        secretAccessKey: secretAccessKey,
                        healthPath: Self.valueOrDefault(healthPath, default: ConnectionProfile.defaultHealthPath),
                        s3Domain: Self.valueOrDefault(s3Domain, default: ConnectionProfile.defaultS3Domain),
                        apiGatewayDomain: Self.valueOrDefault(apiGatewayDomain, default: ConnectionProfile.defaultApiGatewayDomain)
                    )
                    onSave(profile)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 400, height: existing != nil ? 500 : 440)
        .alert("Delete Connection?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete?()
                dismiss()
            }
        } message: {
            if let existing {
                Text("\(existing.name)\n\(existing.endpoint)\nRegion: \(existing.region)")
            }
        }
    }

    @ViewBuilder
    private func testResultLabel(_ result: TestResult) -> some View {
        switch result {
        case .success(let message):
            Label(message, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .failure(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        }
    }

    private func testConnection() {
        let path = Self.valueOrDefault(healthPath, default: ConnectionProfile.defaultHealthPath)
        guard let url = URL(string: endpoint.hasSuffix("/")
            ? endpoint + path
            : endpoint + "/" + path) else {
            testResult = .failure("Invalid URL")
            return
        }

        isTesting = true
        testResult = nil
        Log.info("Testing connection to \(url.absoluteString)", category: "Connection")

        Task {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 5
                let (data, response) = try await URLSession.shared.data(for: request)

                guard let http = response as? HTTPURLResponse else {
                    Log.error("Test connection: non-HTTP response from \(endpoint)", category: "Connection")
                    testResult = .failure("Invalid response")
                    isTesting = false
                    return
                }

                if (200..<300).contains(http.statusCode) {
                    // Try to extract version from health response
                    var version = ""
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let v = json["version"] as? String {
                        version = " (v\(v))"
                    }
                    Log.info("Test connection OK: \(endpoint) -> \(http.statusCode)\(version)", category: "Connection")
                    testResult = .success("Connected\(version)")
                } else {
                    Log.warn("Test connection failed: \(endpoint) -> HTTP \(http.statusCode)", category: "Connection")
                    testResult = .failure("HTTP \(http.statusCode)")
                }
            } catch {
                Log.error("Test connection failed: \(endpoint) -> \(error.localizedDescription)", category: "Connection")
                testResult = .failure(error.localizedDescription)
            }
            isTesting = false
        }
    }

    /// Returns empty string when the value matches the default, so the placeholder shows through.
    private static func customOrEmpty(_ value: String?, default fallback: String) -> String {
        guard let value else { return "" }
        return value == fallback ? "" : value
    }

    /// Returns the default when the field is blank.
    private static func valueOrDefault(_ value: String, default fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
