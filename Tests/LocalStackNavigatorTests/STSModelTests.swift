import Testing
import Foundation
@testable import LocalStackNavigator

@Suite("STS Models")
struct STSModelTests {

    // MARK: - CallerIdentity CLI

    @Test("getCallerIdentityCLI generates valid command")
    func getCallerIdentityCLI() {
        let cli = CallerIdentity.getCallerIdentityCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws sts get-caller-identity"))
        #expect(cli.contains("http://localhost:4566"))
        #expect(cli.contains("us-east-1"))
    }
}
