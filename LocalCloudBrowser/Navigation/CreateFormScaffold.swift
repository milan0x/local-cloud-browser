import SwiftUI

/// Shared scaffold for all resource creation sheets.
/// Wraps form content with consistent layout: Form → validation → Divider → Cancel/Create buttons.
struct CreateFormScaffold<Content: View>: View {
    @Environment(\.dismiss) private var dismiss

    let width: CGFloat
    let minHeight: CGFloat?
    let isValid: Bool
    let isCreating: Bool
    let createLabel: String
    @Binding var serviceError: ServiceError?
    let onCreate: () -> Void
    @ViewBuilder let content: Content

    init(
        width: CGFloat = 380,
        minHeight: CGFloat? = nil,
        isValid: Bool,
        isCreating: Bool,
        createLabel: String = "Create",
        serviceError: Binding<ServiceError?>,
        onCreate: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.width = width
        self.minHeight = minHeight
        self.isValid = isValid
        self.isCreating = isCreating
        self.createLabel = createLabel
        self._serviceError = serviceError
        self.onCreate = onCreate
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                content
            }
            .formStyle(.grouped)

            Divider()
                .padding(.top, 8)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(createLabel) { onCreate() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid || isCreating)
            }
            .padding()
        }
        .frame(width: width)
        .frame(minHeight: minHeight ?? 0)
        .serviceErrorAlert(error: $serviceError)
    }
}
