import SwiftUI

private struct ServiceErrorAlertModifier: ViewModifier {
    @Binding var error: ServiceError?
    @Binding var retryAction: (() -> Void)?

    func body(content: Content) -> some View {
        content.alert(
            error?.code ?? "Error",
            isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil; retryAction = nil } }
            ),
            presenting: error
        ) { _ in
            if retryAction != nil {
                Button("Retry") { retryAction?() }
                Button("OK", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: { serviceError in
            Text(serviceError.friendlyMessage)
        }
    }
}

extension View {
    func serviceErrorAlert(error: Binding<ServiceError?>, retryAction: Binding<(() -> Void)?>) -> some View {
        modifier(ServiceErrorAlertModifier(error: error, retryAction: retryAction))
    }

    func serviceErrorAlert(error: Binding<ServiceError?>) -> some View {
        modifier(ServiceErrorAlertModifier(error: error, retryAction: .constant(nil)))
    }
}
