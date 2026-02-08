import SwiftUI

struct SQSModuleView: View {
    var body: some View {
        ModulePlaceholderView(
            serviceName: "SQS",
            systemImage: "tray.2",
            description: "View queues, send and receive messages, manage queue attributes."
        )
    }
}

struct SQSModule: LocalStackModule {
    let serviceName = "SQS"
    let serviceIcon = "tray.2"
    let serviceEndpoint = "/sqs"

    func makeMainView() -> AnyView {
        AnyView(SQSModuleView())
    }
}
