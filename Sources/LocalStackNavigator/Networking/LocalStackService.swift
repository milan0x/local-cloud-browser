import Foundation

@MainActor
class LocalStackService: ObservableObject {
    private(set) var client: LocalStackClient!

    func updateClient(_ newClient: LocalStackClient) {
        self.client = newClient
    }
}
