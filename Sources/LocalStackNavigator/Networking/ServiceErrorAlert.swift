import SwiftUI

private struct ServiceErrorAlertModifier: ViewModifier {
    @Binding var error: ServiceError?

    func body(content: Content) -> some View {
        content.alert(
            error?.code ?? "Error",
            isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            ),
            presenting: error
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { serviceError in
            Text(serviceError.friendlyMessage)
        }
    }
}

extension View {
    func serviceErrorAlert(error: Binding<ServiceError?>) -> some View {
        modifier(ServiceErrorAlertModifier(error: error))
    }
}
