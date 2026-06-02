import SwiftUI

struct S3CreateBucketView: View {
    @ObservedObject var service: S3Service
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var bucketName = ""
    @State private var region = ""
    @State private var serviceError: ServiceError?
    @State private var isCreating = false
    var existingBucketNames: Set<String> = []
    var onCreate: ((String) -> Void)? = nil

    var body: some View {
        CreateFormScaffold(
            isValid: isValid,
            isCreating: isCreating,
            serviceError: $serviceError,
            onCreate: create
        ) {
            TextField("Bucket name", text: $bucketName)
                .onChange(of: bucketName) {
                    let lowered = bucketName.lowercased()
                    if lowered != bucketName { bucketName = lowered }
                }
            LabeledContent("Region") {
                AWSRegionPicker(regionCode: $region)
            }

            Section {
                Label("S3 buckets are global — no region isolation.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if nameExists {
                Text("A bucket named \"\(bucketName.trimmingCharacters(in: .whitespaces))\" already exists.")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .onAppear { region = appState.region }
    }

    private var nameExists: Bool {
        let name = bucketName.trimmingCharacters(in: .whitespaces)
        return !name.isEmpty && existingBucketNames.contains(name)
    }

    private var isValid: Bool {
        let name = bucketName.trimmingCharacters(in: .whitespaces)
        guard name.count >= 3, name.count <= 63 else { return false }
        let allowed = CharacterSet.lowercaseLetters
            .union(.decimalDigits)
            .union(CharacterSet(charactersIn: ".-"))
        return name.unicodeScalars.allSatisfy { allowed.contains($0) } && !nameExists
    }

    private func create() {
        let name = bucketName.trimmingCharacters(in: .whitespaces)
        isCreating = true
        serviceError = nil
        Task {
            do {
                let regionValue = region.trimmingCharacters(in: .whitespaces)
                try await service.createBucket(name: name, region: regionValue.isEmpty ? nil : regionValue)
                onCreate?(name)
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isCreating = false
            }
        }
    }
}
