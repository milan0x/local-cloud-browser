import Testing
@testable import LocalCloudBrowser

struct EndpointDetectionTests {

    // MARK: - EndpointType Codable

    @Test func endpointTypeCodableRoundTrip() throws {
        for type in [EndpointType.localstack, .minio, .generic] {
            let data = try JSONEncoder().encode(type)
            let decoded = try JSONDecoder().decode(EndpointType.self, from: data)
            #expect(decoded == type)
        }
    }

    @Test func endpointTypeRawValues() {
        #expect(EndpointType.localstack.rawValue == "localstack")
        #expect(EndpointType.minio.rawValue == "minio")
        #expect(EndpointType.generic.rawValue == "generic")
    }

    // MARK: - DetectedSettings

    @Test func detectedSettingsEmptyWhenAllNil() {
        let settings = DetectedSettings()
        #expect(settings.isEmpty)
        #expect(settings.detectedFieldNames.isEmpty)
    }

    @Test func detectedSettingsNotEmptyWithEndpointType() {
        var settings = DetectedSettings()
        settings.endpointType = .minio
        #expect(!settings.isEmpty)
        #expect(settings.detectedFieldNames == ["endpointType"])
    }

    @Test func detectedSettingsNotEmptyWithHealthPath() {
        var settings = DetectedSettings()
        settings.healthPath = "minio/health/live"
        #expect(!settings.isEmpty)
        #expect(settings.detectedFieldNames == ["healthPath"])
    }

    @Test func detectedSettingsMultipleFields() {
        var settings = DetectedSettings()
        settings.endpointType = .localstack
        settings.healthPath = "_localstack/health"
        settings.s3Domain = "s3.localhost.localstack.cloud"
        settings.apiGatewayDomain = "execute-api.localhost.localstack.cloud"
        #expect(!settings.isEmpty)
        #expect(settings.detectedFieldNames.count == 4)
        #expect(settings.detectedFieldNames.contains("endpointType"))
        #expect(settings.detectedFieldNames.contains("healthPath"))
        #expect(settings.detectedFieldNames.contains("s3Domain"))
        #expect(settings.detectedFieldNames.contains("apiGatewayDomain"))
    }

    // MARK: - ConnectionProfile endpointType persistence

    @Test func connectionProfileDefaultsToGeneric() {
        let profile = ConnectionProfile()
        #expect(profile.endpointType == .generic)
    }

    @Test func connectionProfileCodablePreservesEndpointType() throws {
        let profile = ConnectionProfile(
            name: "Test MinIO",
            endpoint: "http://localhost:9000",
            endpointType: .minio
        )
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(ConnectionProfile.self, from: data)
        #expect(decoded.endpointType == .minio)
        #expect(decoded.name == "Test MinIO")
        #expect(decoded.endpoint == "http://localhost:9000")
    }

    @Test func connectionProfileDecodesGenericWhenKeyMissing() throws {
        // Simulate a profile saved before endpointType was added
        let json = """
        {"id":"00000000-0000-0000-0000-000000000000","name":"Old","endpoint":"http://localhost:4566","region":"us-east-1"}
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(ConnectionProfile.self, from: data)
        #expect(decoded.endpointType == .generic)
    }

    @Test func connectionProfileMinioRegionLock() {
        let profile = ConnectionProfile(
            endpoint: "http://localhost:9000",
            region: "eu-west-1",
            endpointType: .minio
        )
        // The profile stores the region as-is; the lock is enforced by AppState.applyProfile
        #expect(profile.region == "eu-west-1")
        #expect(profile.endpointType == .minio)
    }
}
