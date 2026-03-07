import Foundation

@MainActor
class BaseService: ObservableObject {
    private(set) var client: CloudClient!

    func updateClient(_ newClient: CloudClient) {
        self.client = newClient
    }
}
