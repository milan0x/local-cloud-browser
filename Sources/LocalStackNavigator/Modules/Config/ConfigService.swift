import Foundation

final class ConfigService: LocalStackService {
    // MARK: - Configuration Recorders

    func describeConfigurationRecorders(region: String? = nil) async throws -> [ConfigurationRecorder] {
        let data = try await client.configRequest(action: "DescribeConfigurationRecorders", payload: [:], region: region)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let recorders = json["ConfigurationRecorders"] as? [[String: Any]] else {
            return []
        }
        return recorders.map { ConfigurationRecorder(from: $0) }
    }

    func describeConfigurationRecorderStatus(names: [String] = []) async throws -> [ConfigurationRecorderStatus] {
        var payload: [String: Any] = [:]
        if !names.isEmpty {
            payload["ConfigurationRecorderNames"] = names
        }
        let data = try await client.configRequest(action: "DescribeConfigurationRecorderStatus", payload: payload)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let statuses = json["ConfigurationRecordersStatus"] as? [[String: Any]] else {
            return []
        }
        return statuses.map { ConfigurationRecorderStatus(from: $0) }
    }

    func putConfigurationRecorder(name: String, roleARN: String, allSupported: Bool, resourceTypes: [String]) async throws {
        var recordingGroup: [String: Any] = ["allSupported": allSupported]
        if !allSupported && !resourceTypes.isEmpty {
            recordingGroup["resourceTypes"] = resourceTypes
        }
        let payload: [String: Any] = [
            "ConfigurationRecorder": [
                "name": name,
                "roleARN": roleARN,
                "recordingGroup": recordingGroup,
            ]
        ]
        _ = try await client.configRequest(action: "PutConfigurationRecorder", payload: payload)
    }

    func deleteConfigurationRecorder(name: String) async throws {
        _ = try await client.configRequest(
            action: "DeleteConfigurationRecorder",
            payload: ["ConfigurationRecorderName": name]
        )
    }

    func startConfigurationRecorder(name: String) async throws {
        _ = try await client.configRequest(
            action: "StartConfigurationRecorder",
            payload: ["ConfigurationRecorderName": name]
        )
    }

    func stopConfigurationRecorder(name: String) async throws {
        _ = try await client.configRequest(
            action: "StopConfigurationRecorder",
            payload: ["ConfigurationRecorderName": name]
        )
    }

    // MARK: - Delivery Channels

    func describeDeliveryChannels() async throws -> [DeliveryChannel] {
        let data = try await client.configRequest(action: "DescribeDeliveryChannels", payload: [:])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let channels = json["DeliveryChannels"] as? [[String: Any]] else {
            return []
        }
        return channels.map { DeliveryChannel(from: $0) }
    }

    func putDeliveryChannel(name: String, s3BucketName: String, s3KeyPrefix: String?, snsTopicARN: String?, frequency: String?) async throws {
        var channel: [String: Any] = [
            "name": name,
            "s3BucketName": s3BucketName,
        ]
        if let prefix = s3KeyPrefix, !prefix.isEmpty {
            channel["s3KeyPrefix"] = prefix
        }
        if let topic = snsTopicARN, !topic.isEmpty {
            channel["snsTopicARN"] = topic
        }
        if let freq = frequency, !freq.isEmpty {
            channel["configSnapshotDeliveryProperties"] = ["deliveryFrequency": freq]
        }
        _ = try await client.configRequest(
            action: "PutDeliveryChannel",
            payload: ["DeliveryChannel": channel]
        )
    }

    func deleteDeliveryChannel(name: String) async throws {
        _ = try await client.configRequest(
            action: "DeleteDeliveryChannel",
            payload: ["DeliveryChannelName": name]
        )
    }
}
