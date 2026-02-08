import SwiftUI

struct SNSModuleView: View {
    var body: some View {
        ModulePlaceholderView(
            serviceName: "SNS",
            systemImage: "bell",
            description: "Manage topics, subscriptions, and publish notifications."
        )
    }
}

struct SNSModule: LocalStackModule {
    let serviceName = "SNS"
    let serviceIcon = "bell"
    let serviceEndpoint = "/sns"

    func makeMainView() -> AnyView {
        AnyView(SNSModuleView())
    }
}
