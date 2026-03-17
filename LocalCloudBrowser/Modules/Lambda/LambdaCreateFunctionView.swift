import SwiftUI
import UniformTypeIdentifiers

struct LambdaCreateFunctionView: View {
    @ObservedObject var service: LambdaService
    @EnvironmentObject private var licenseManager: LicenseManager
    @Environment(\.dismiss) private var dismiss
    @State private var functionName = ""
    @State private var runtime = "python3.12"
    @State private var handler = "lambda_function.lambda_handler"
    @State private var role = "arn:aws:iam::000000000000:role/lambda-role"
    @State private var functionDescription = ""
    @State private var timeout = 3
    @State private var memorySize = 128
    @State private var environmentKeys: [String] = []
    @State private var environmentValues: [String] = []
    @State private var zipData: Data?
    @State private var zipFileName: String?
    @State private var serviceError: ServiceError?
    @State private var isSaving = false
    var existingFunctionNames: Set<String>
    var onCreate: ((String) -> Void)? = nil

    // Edit mode
    var editingFunction: LambdaFunction?

    private var isEditing: Bool { editingFunction != nil }

    private static let runtimes: [(group: String, values: [(label: String, value: String)])] = [
        ("Python", [
            ("python3.12", "python3.12"),
            ("python3.11", "python3.11"),
            ("python3.10", "python3.10"),
            ("python3.9", "python3.9"),
        ]),
        ("Node.js", [
            ("nodejs20.x", "nodejs20.x"),
            ("nodejs18.x", "nodejs18.x"),
            ("nodejs16.x", "nodejs16.x"),
        ]),
        ("Java", [
            ("java21", "java21"),
            ("java17", "java17"),
            ("java11", "java11"),
        ]),
        (".NET", [
            ("dotnet8", "dotnet8"),
            ("dotnet6", "dotnet6"),
        ]),
        ("Ruby", [
            ("ruby3.3", "ruby3.3"),
            ("ruby3.2", "ruby3.2"),
        ]),
        ("Custom", [
            ("provided.al2023", "provided.al2023"),
            ("provided.al2", "provided.al2"),
        ]),
    ]

    init(service: LambdaService, existingFunctionNames: Set<String>, onCreate: ((String) -> Void)? = nil, editingFunction: LambdaFunction? = nil) {
        self.service = service
        self.existingFunctionNames = existingFunctionNames
        self.onCreate = onCreate
        self.editingFunction = editingFunction
        if let fn = editingFunction {
            _functionName = State(initialValue: fn.functionName)
            _runtime = State(initialValue: fn.runtime.isEmpty ? "python3.12" : fn.runtime)
            _handler = State(initialValue: fn.handler)
            _role = State(initialValue: fn.role)
            _functionDescription = State(initialValue: fn.description)
            _timeout = State(initialValue: fn.timeout)
            _memorySize = State(initialValue: fn.memorySize)
            let sortedEnv = fn.environment.sorted { $0.key < $1.key }
            _environmentKeys = State(initialValue: sortedEnv.map(\.key))
            _environmentValues = State(initialValue: sortedEnv.map(\.value))
        }
    }

    var body: some View {
        CreateFormScaffold(
            width: 520,
            minHeight: 550,
            isValid: isValid,
            isCreating: isSaving,
            createLabel: isEditing ? "Update" : "Create",
            serviceError: $serviceError,
            onCreate: save
        ) {
                Section("Function") {
                    TextField("Function name", text: $functionName)
                        .disabled(isEditing)

                    Picker("Runtime", selection: $runtime) {
                        ForEach(Self.runtimes, id: \.group) { group in
                            Section(group.group) {
                                ForEach(group.values, id: \.value) { item in
                                    Text(item.label).tag(item.value)
                                }
                            }
                        }
                    }
                    .onChange(of: runtime) {
                        if !isEditing {
                            handler = defaultHandler(for: runtime)
                        }
                    }

                    TextField("Handler", text: $handler)

                    TextField("Role ARN", text: $role)
                }

                Section("Options") {
                    TextField("Description (optional)", text: $functionDescription)

                    Stepper("Timeout: \(timeout)s", value: $timeout, in: 1...900)

                    Stepper("Memory: \(memorySize) MB", value: $memorySize, in: 128...10240, step: 64)
                }

                Section("Environment Variables") {
                    ForEach(environmentKeys.indices, id: \.self) { index in
                        HStack(spacing: 4) {
                            TextField("Key", text: Binding(
                                get: { environmentKeys[index] },
                                set: { environmentKeys[index] = $0 }
                            ))
                            .frame(maxWidth: .infinity)
                            Text("=")
                                .foregroundStyle(.secondary)
                            TextField("Value", text: Binding(
                                get: { environmentValues[index] },
                                set: { environmentValues[index] = $0 }
                            ))
                            .frame(maxWidth: .infinity)
                            Button {
                                environmentKeys.remove(at: index)
                                environmentValues.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    Button("Add Variable") {
                        environmentKeys.append("")
                        environmentValues.append("")
                    }
                    .buttonStyle(.borderless)
                }

                if !isEditing {
                    Section("Code") {
                        HStack {
                            if let zipFileName {
                                Image(systemName: "doc.zipper")
                                    .foregroundStyle(.blue)
                                Text(zipFileName)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Change") { pickZipFile() }
                                    .buttonStyle(.borderless)
                            } else {
                                Text("No file selected")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Select ZIP File") { pickZipFile() }
                                    .buttonStyle(.borderless)
                            }
                        }
                        if let zipData {
                            let formatter = ByteCountFormatter()
                            Text("Size: \(formatter.string(fromByteCount: Int64(zipData.count)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

            if nameExists {
                Text("A function named \"\(functionName.trimmingCharacters(in: .whitespaces))\" already exists.")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }
        }
    }

    private var nameExists: Bool {
        let name = functionName.trimmingCharacters(in: .whitespaces)
        return !isEditing && !name.isEmpty && existingFunctionNames.contains(name)
    }

    private var isValid: Bool {
        let name = functionName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return false }
        guard !handler.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard !role.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if !isEditing && zipData == nil { return false }
        return !nameExists
    }

    private func defaultHandler(for runtime: String) -> String {
        if runtime.hasPrefix("python") { return "lambda_function.lambda_handler" }
        if runtime.hasPrefix("nodejs") { return "index.handler" }
        if runtime.hasPrefix("java") { return "example.Handler::handleRequest" }
        if runtime.hasPrefix("dotnet") { return "Assembly::Namespace.Class::Method" }
        if runtime.hasPrefix("ruby") { return "lambda_function.LambdaFunction::Handler.process" }
        return "bootstrap"
    }

    private func pickZipFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "zip") ?? .archive]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select a ZIP file containing your Lambda function code"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            zipData = try Data(contentsOf: url)
            zipFileName = url.lastPathComponent
        } catch {
            serviceError = ServiceError(code: "FileError", message: error.localizedDescription)
        }
    }

    private func buildEnvironment() -> [String: String] {
        var env: [String: String] = [:]
        for i in environmentKeys.indices {
            let key = environmentKeys[i].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty {
                env[key] = environmentValues[i]
            }
        }
        return env
    }

    private func save() {
        isSaving = true
        serviceError = nil
        Task {
            do {
                let name = functionName.trimmingCharacters(in: .whitespaces)
                let desc = functionDescription.trimmingCharacters(in: .whitespaces)
                let env = buildEnvironment()

                if isEditing {
                    try await service.updateFunctionConfiguration(
                        name: name,
                        description: desc,
                        timeout: timeout,
                        memorySize: memorySize,
                        handler: handler.trimmingCharacters(in: .whitespaces),
                        runtime: runtime,
                        environment: env
                    )
                } else {
                    try await service.createFunction(
                        name: name,
                        runtime: runtime,
                        handler: handler.trimmingCharacters(in: .whitespaces),
                        role: role.trimmingCharacters(in: .whitespaces),
                        zipData: zipData!,
                        description: desc.isEmpty ? nil : desc,
                        timeout: timeout,
                        memorySize: memorySize,
                        environment: env
                    )
                }
                if !isEditing {
                    licenseManager.incrementCreateCount(for: .lambda)
                    onCreate?(name)
                }
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
