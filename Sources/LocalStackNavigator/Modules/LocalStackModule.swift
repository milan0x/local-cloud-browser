import SwiftUI

protocol LocalStackModule {
    var serviceName: String { get }
    var serviceIcon: String { get }
    var serviceEndpoint: String { get }

    @ViewBuilder @MainActor
    func makeMainView() -> AnyView

    @MainActor
    func makeSidebarDetail() -> AnyView?
}

extension LocalStackModule {
    func makeSidebarDetail() -> AnyView? { nil }
}
