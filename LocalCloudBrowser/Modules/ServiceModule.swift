import SwiftUI

protocol ServiceModule {
    var serviceName: String { get }
    var serviceIcon: String { get }
    var serviceEndpoint: String { get }

    @ViewBuilder @MainActor
    func makeMainView() -> AnyView

    @MainActor
    func makeSidebarDetail() -> AnyView?
}

extension ServiceModule {
    func makeSidebarDetail() -> AnyView? { nil }
}
