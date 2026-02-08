import SwiftUI

struct SecretsManagerModuleView: View {
    var body: some View {
        ModulePlaceholderView(
            serviceName: "Secrets Manager",
            systemImage: "key",
            description: "Store, retrieve, and rotate secrets securely."
        )
    }
}

struct SecretsManagerModule: LocalStackModule {
    let serviceName = "Secrets Manager"
    let serviceIcon = "key"
    let serviceEndpoint = "/secretsmanager"

    func makeMainView() -> AnyView {
        AnyView(SecretsManagerModuleView())
    }
}
