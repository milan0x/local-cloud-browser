import SwiftUI

struct S3CreateBucketView: View {
    @ObservedObject var service: S3Service
    @Environment(\.dismiss) private var dismiss
    @State private var bucketName = ""
    @State private var errorMessage: String?
    @State private var isCreating = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Create Bucket")
                .font(.headline)

            TextField("Bucket name", text: $bucketName)
                .textFieldStyle(.roundedBorder)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid || isCreating)
            }
        }
        .padding()
        .frame(width: 320)
    }

    private var isValid: Bool {
        let name = bucketName.trimmingCharacters(in: .whitespaces)
        guard name.count >= 3, name.count <= 63 else { return false }
        let allowed = CharacterSet.lowercaseLetters
            .union(.decimalDigits)
            .union(CharacterSet(charactersIn: ".-"))
        return name.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private func create() {
        let name = bucketName.trimmingCharacters(in: .whitespaces)
        isCreating = true
        errorMessage = nil
        Task {
            do {
                try await service.createBucket(name: name)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isCreating = false
            }
        }
    }
}
