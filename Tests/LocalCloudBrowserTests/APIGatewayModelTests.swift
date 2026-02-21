import Testing
import Foundation
@testable import LocalCloudBrowser

@Suite("API Gateway Models")
struct APIGatewayModelTests {

    // MARK: - RestApi

    @Test("endpointType returns first type or defaults to REGIONAL")
    func endpointType() {
        let api = RestApi(from: [
            "id": "abc123",
            "name": "my-api",
            "endpointConfiguration": ["types": ["EDGE"]],
        ])
        #expect(api.endpointType == "EDGE")

        let apiDefault = RestApi(from: ["id": "x", "name": "y"])
        #expect(apiDefault.endpointType == "REGIONAL")
    }

    @Test("RestApi parses all fields")
    func restApiInit() {
        let api = RestApi(from: [
            "id": "abc",
            "name": "My API",
            "description": "Test API",
            "createdDate": "2024-01-15",
            "version": "1.0",
            "apiKeySource": "HEADER",
        ])
        #expect(api.id == "abc")
        #expect(api.name == "My API")
        #expect(api.description == "Test API")
        #expect(api.apiKeySource == "HEADER")
    }

    // MARK: - APIResource

    @Test("isRoot for root path")
    func isRoot() {
        let root = APIResource(from: ["id": "r1", "path": "/"])
        #expect(root.isRoot == true)

        let nested = APIResource(from: ["id": "r2", "path": "/users"])
        #expect(nested.isRoot == false)
    }

    @Test("methods parsed from resourceMethods keys")
    func resourceMethods() {
        let resource = APIResource(from: [
            "id": "r1",
            "path": "/users",
            "resourceMethods": ["GET": [:], "POST": [:], "DELETE": [:]],
        ])
        #expect(resource.methods == ["DELETE", "GET", "POST"])
    }

    @Test("methods empty when no resourceMethods")
    func resourceMethodsEmpty() {
        let resource = APIResource(from: ["id": "r1", "path": "/"])
        #expect(resource.methods.isEmpty)
    }

    // MARK: - APIMethod

    @Test("APIMethod parses integration")
    func methodIntegration() {
        let method = APIMethod(from: [
            "httpMethod": "GET",
            "authorizationType": "NONE",
            "apiKeyRequired": false,
            "methodIntegration": [
                "type": "AWS_PROXY",
                "uri": "arn:aws:lambda:us-east-1:000:function:my-func",
            ],
        ])
        #expect(method.integration?.type == "AWS_PROXY")
    }

    // MARK: - APIStage

    @Test("invokeUrl generates correct URL")
    func invokeUrl() {
        let stage = APIStage(from: [
            "stageName": "prod",
            "deploymentId": "d1",
        ])
        let url = stage.invokeUrl(apiId: "abc123", domain: "execute-api.localhost", port: 4566)
        #expect(url == "http://abc123.execute-api.localhost:4566/prod/")
    }

    @Test("pathStyleInvokeUrl generates correct URL")
    func pathStyleInvokeUrl() {
        let stage = APIStage(from: [
            "stageName": "dev",
            "deploymentId": "d1",
        ])
        let url = stage.pathStyleInvokeUrl(apiId: "abc", endpoint: "http://localhost:4566")
        #expect(url == "http://localhost:4566/_aws/execute-api/abc/dev/")
    }

    // MARK: - CLI

    @Test("getRestApiCLI generates valid command")
    func getRestApiCLI() {
        let api = RestApi(from: ["id": "abc", "name": "test"])
        let cli = api.getRestApiCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws apigateway get-rest-api"))
        #expect(cli.contains("abc"))
    }

    @Test("getResourcesCLI generates valid command")
    func getResourcesCLI() {
        let api = RestApi(from: ["id": "abc", "name": "test"])
        let cli = api.getResourcesCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws apigateway get-resources"))
    }

    @Test("listRestApisCLI generates valid command")
    func listRestApisCLI() {
        let cli = RestApi.listRestApisCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws apigateway get-rest-apis"))
    }
}
