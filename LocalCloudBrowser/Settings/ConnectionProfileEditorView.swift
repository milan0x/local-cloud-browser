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
    @State private var endpointType: EndpointType
    @State private var testResult: TestResult?
    @State private var isTesting = false
    @State private var isDetecting = false
    @State private var detectedFields: Set<String> = []
    @State private var notDetectedFields: [String] = []
    @State private var showDeleteConfirmation = false
    @State private var showAdvanced = false
    @FocusState private var focusedField: String?

    enum TestResult {
        case success(String)
        case failure(String)
    }

    init(existing: ConnectionProfile? = nil, canDelete: Bool = false, showAdvanced: Bool = false, onSave: @escaping (ConnectionProfile) -> Void, onDelete: (() -> Void)? = nil) {
        self.existing = existing
        self.canDelete = canDelete
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: existing?.name ?? "")
        _endpoint = State(initialValue: existing?.endpoint ?? "")
        _region = State(initialValue: existing?.region ?? "us-east-1")
        _accessKeyId = State(initialValue: existing?.accessKeyId ?? "")
        _secretAccessKey = State(initialValue: existing?.secretAccessKey ?? "")
        _healthPath = State(initialValue: existing?.healthPath ?? "")
        _s3Domain = State(initialValue: existing?.s3Domain ?? "")
        _apiGatewayDomain = State(initialValue: existing?.apiGatewayDomain ?? "")
        _endpointType = State(initialValue: existing?.endpointType ?? .generic)
        _showAdvanced = State(initialValue: showAdvanced)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !endpoint.trimmingCharacters(in: .whitespaces).isEmpty
            && URL(string: endpoint) != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Name", text: $name)
                    .focused($focusedField, equals: "name")
                    .textFieldStyle(.roundedBorder)
                TextField("Endpoint", text: $endpoint, prompt: Text("http://localhost:port"))
                    .textFieldStyle(.roundedBorder)
                LabeledContent("Default Region") {
                    if endpointType == .minio {
                        Text("us-east-1")
                            .foregroundStyle(.secondary)
                    } else {
                        AWSRegionPicker(regionCode: $region)
                    }
                }
                TextField("Access Key ID", text: $accessKeyId, prompt: Text("Access Key ID"))
                    .textFieldStyle(.roundedBorder)
                SecureField("Secret Access Key", text: $secretAccessKey, prompt: Text("Secret Access Key"))
                    .textFieldStyle(.roundedBorder)

                DisclosureGroup(isExpanded: $showAdvanced) {
                    advancedField(
                        label: "Health Check Path",
                        text: $healthPath,
                        prompt: "e.g. health",
                        fieldKey: "healthPath"
                    )
                    advancedField(
                        label: "S3 Domain",
                        text: $s3Domain,
                        prompt: "e.g. s3.localhost",
                        fieldKey: "s3Domain"
                    )
                    advancedField(
                        label: "API Gateway Domain",
                        text: $apiGatewayDomain,
                        prompt: "e.g. execute-api.localhost",
                        fieldKey: "apiGatewayDomain"
                    )
                } label: {
                    HStack(spacing: 6) {
                        Text("Advanced")
                        if isDetecting {
                            ProgressView()
                                .controlSize(.mini)
                        }
                    }
                    .onTapGesture { showAdvanced.toggle() }
                }

                Section {
                    if testResult == nil && !isTesting {
                        Label("Testing is recommended to auto-detect settings", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

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

                    if !detectedFields.isEmpty || !notDetectedFields.isEmpty {
                        detectionSummary
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
                        healthPath: healthPath.trimmingCharacters(in: .whitespaces),
                        s3Domain: s3Domain.trimmingCharacters(in: .whitespaces),
                        apiGatewayDomain: apiGatewayDomain.trimmingCharacters(in: .whitespaces),
                        endpointType: endpointType
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

    @ViewBuilder
    private func advancedField(label: String, text: Binding<String>, prompt: String, fieldKey: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if detectedFields.contains(fieldKey) {
                    Text("Auto-detected")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }
            TextField("", text: Binding(
                get: { text.wrappedValue },
                set: { newValue in
                    text.wrappedValue = newValue
                    detectedFields.remove(fieldKey)
                }
            ), prompt: Text(prompt))
                .textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var detectionSummary: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(detectedFields).sorted(), id: \.self) { field in
                Label(fieldLabel(for: field), systemImage: "checkmark")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            ForEach(notDetectedFields, id: \.self) { field in
                Label(fieldLabel(for: field), systemImage: "minus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func fieldLabel(for key: String) -> String {
        switch key {
        case "endpointType": return "Endpoint: \(endpointType.rawValue.capitalized)"
        case "healthPath": return "Health Path"
        case "s3Domain": return "S3 Domain"
        case "apiGatewayDomain": return "API Gateway Domain"
        default: return key
        }
    }

    private func testConnection() {
        guard URL(string: endpoint) != nil else {
            testResult = .failure("Invalid URL")
            return
        }

        isTesting = true
        testResult = nil
        detectedFields = []
        notDetectedFields = []
        showAdvanced = true
        Log.info("Testing connection to \(endpoint)", category: "Connection")

        Task {
            // Step 1: Detect endpoint type and settings first.
            // This discovers the correct health path for MinIO / LocalStack
            // so we don't hit the root endpoint unsigned.
            if SafetyGuard.evaluate(endpoint: endpoint) == .local {
                isDetecting = true
                let result = await EndpointDetector.detect(
                    endpoint: endpoint,
                    currentHealthPath: healthPath,
                    currentS3Domain: s3Domain,
                    currentApiGatewayDomain: apiGatewayDomain
                )

                var filled: Set<String> = []
                var probed: [String] = ["endpointType"]
                if healthPath.trimmingCharacters(in: .whitespaces).isEmpty { probed.append("healthPath") }
                if s3Domain.trimmingCharacters(in: .whitespaces).isEmpty { probed.append("s3Domain") }
                if apiGatewayDomain.trimmingCharacters(in: .whitespaces).isEmpty { probed.append("apiGatewayDomain") }

                if let value = result.endpointType {
                    endpointType = value
                    filled.insert("endpointType")
                    // Auto-fill credentials and region based on detected type
                    switch value {
                    case .minio:
                        region = "us-east-1"
                        if accessKeyId.isEmpty { accessKeyId = "minioadmin" }
                        if secretAccessKey.isEmpty { secretAccessKey = "minioadmin" }
                    case .localstack:
                        if accessKeyId.isEmpty { accessKeyId = "test" }
                        if secretAccessKey.isEmpty { secretAccessKey = "test" }
                    case .generic:
                        break
                    }
                }
                if let value = result.healthPath {
                    healthPath = value
                    filled.insert("healthPath")
                }
                if let value = result.s3Domain {
                    s3Domain = value
                    filled.insert("s3Domain")
                }
                if let value = result.apiGatewayDomain {
                    apiGatewayDomain = value
                    filled.insert("apiGatewayDomain")
                }

                detectedFields = filled
                notDetectedFields = probed.filter { !filled.contains($0) }
                isDetecting = false
            }

            // Step 2: Test connection using the (possibly updated) health path
            let trimmedPath = healthPath.trimmingCharacters(in: .whitespaces)
            let testURL: String
            if trimmedPath.isEmpty {
                testURL = endpoint
            } else {
                testURL = endpoint.hasSuffix("/") ? endpoint + trimmedPath : endpoint + "/" + trimmedPath
            }

            guard let url = URL(string: testURL) else {
                testResult = .failure("Invalid URL")
                isTesting = false
                return
            }

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
                    var suffix = ""
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let v = json["version"] as? String {
                        suffix = " (v\(v))"
                    } else if endpointType == .minio {
                        suffix = " (MinIO)"
                    }
                    Log.info("Test connection OK: \(endpoint) -> \(http.statusCode)\(suffix)", category: "Connection")
                    testResult = .success("Connected\(suffix)")
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


}
