import SwiftUI

struct APIGatewayCreateResourceView: View {
    @ObservedObject var service: APIGatewayService
    let apiId: String
    let resources: [APIResource]
    @Environment(\.dismiss) private var dismiss
    @State private var parentId = ""
    @State private var pathPart = ""
    @State private var serviceError: ServiceError?
    @State private var isSaving = false

    private static let validPathPattern = try! NSRegularExpression(pattern: "^[a-zA-Z0-9._\\-{}+]+$")

    var body: some View {
        CreateFormScaffold(
            width: 420,
            minHeight: 280,
            isValid: isValid,
            isCreating: isSaving,
            serviceError: $serviceError,
            onCreate: save
        ) {
                Section("Resource") {
                    Picker("Parent Resource", selection: $parentId) {
                        ForEach(resources, id: \.id) { resource in
                            Text(resource.path).tag(resource.id)
                        }
                    }

                    TextField("Path Part", text: $pathPart)
                        .disableAutocorrection(true)
                }

                if !trimmedPathPart.isEmpty {
                    Section("Preview") {
                        Text(fullPath)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

            if !trimmedPathPart.isEmpty && !pathPartIsValid {
                Text("Path part can only contain letters, numbers, and -_.{}+")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }
        }
        .onAppear {
            if let root = resources.first(where: { $0.isRoot }) {
                parentId = root.id
            } else if let first = resources.first {
                parentId = first.id
            }
        }
    }

    private var trimmedPathPart: String {
        pathPart.trimmingCharacters(in: .whitespaces)
    }

    private var pathPartIsValid: Bool {
        let range = NSRange(trimmedPathPart.startIndex..., in: trimmedPathPart)
        return Self.validPathPattern.firstMatch(in: trimmedPathPart, range: range) != nil
    }

    private var fullPath: String {
        let parentPath = resources.first(where: { $0.id == parentId })?.path ?? "/"
        if parentPath == "/" {
            return "/\(trimmedPathPart)"
        }
        return "\(parentPath)/\(trimmedPathPart)"
    }

    private var isValid: Bool {
        !trimmedPathPart.isEmpty && pathPartIsValid && !parentId.isEmpty
    }

    private func save() {
        isSaving = true
        serviceError = nil
        Task {
            do {
                try await service.createResource(apiId: apiId, parentId: parentId, pathPart: trimmedPathPart)
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
