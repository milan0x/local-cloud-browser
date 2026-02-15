import Foundation

@MainActor
final class KinesisFirehoseService: ObservableObject {
    private var client: LocalStackClient!

    func updateClient(_ newClient: LocalStackClient) {
        self.client = newClient
    }

    // MARK: - Delivery Stream Operations

    func listDeliveryStreams() async throws -> [FirehoseDeliveryStreamSummary] {
        var allStreams: [FirehoseDeliveryStreamSummary] = []
        var hasMore = true
        var exclusiveStartName: String?

        while hasMore {
            var payload: [String: Any] = [:]
            if let startName = exclusiveStartName {
                payload["ExclusiveStartDeliveryStreamName"] = startName
            }
            let data = try await client.firehoseRequest(action: "ListDeliveryStreams", payload: payload)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                break
            }
            let names = json["DeliveryStreamNames"] as? [String] ?? []
            hasMore = json["HasMoreDeliveryStreams"] as? Bool ?? false
            exclusiveStartName = names.last

            // ListDeliveryStreams only returns names — describe each for summary info
            for name in names {
                do {
                    let detail = try await describeDeliveryStream(name: name)
                    allStreams.append(FirehoseDeliveryStreamSummary(
                        deliveryStreamName: detail.deliveryStreamName,
                        deliveryStreamARN: detail.deliveryStreamARN,
                        deliveryStreamStatus: detail.deliveryStreamStatus,
                        deliveryStreamType: detail.deliveryStreamType,
                        createTimestamp: detail.createTimestamp
                    ))
                } catch {
                    // If describe fails, add a minimal summary
                    allStreams.append(FirehoseDeliveryStreamSummary(deliveryStreamName: name))
                }
            }
        }

        return allStreams
    }

    func describeDeliveryStream(name: String) async throws -> FirehoseDeliveryStreamDetail {
        let data = try await client.firehoseRequest(
            action: "DescribeDeliveryStream",
            payload: ["DeliveryStreamName": name]
        )
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let desc = json["DeliveryStreamDescription"] as? [String: Any] else {
            throw LocalStackClientError.invalidURL
        }
        return FirehoseDeliveryStreamDetail(from: desc)
    }

    func createDeliveryStream(
        name: String,
        s3BucketARN: String,
        s3Prefix: String,
        bufferingInterval: Int,
        bufferingSize: Int,
        compression: String
    ) async throws {
        let roleARN = "arn:aws:iam::000000000000:role/firehose-role"
        let payload: [String: Any] = [
            "DeliveryStreamName": name,
            "DeliveryStreamType": "DirectPut",
            "ExtendedS3DestinationConfiguration": [
                "BucketARN": s3BucketARN,
                "Prefix": s3Prefix,
                "RoleARN": roleARN,
                "CompressionFormat": compression,
                "BufferingHints": [
                    "IntervalInSeconds": bufferingInterval,
                    "SizeInMBs": bufferingSize,
                ],
            ] as [String: Any],
        ]
        _ = try await client.firehoseRequest(action: "CreateDeliveryStream", payload: payload)
    }

    func deleteDeliveryStream(name: String) async throws {
        _ = try await client.firehoseRequest(
            action: "DeleteDeliveryStream",
            payload: ["DeliveryStreamName": name]
        )
    }

    // MARK: - Put Record

    func putRecord(name: String, data: String) async throws -> String {
        let base64Data = Data(data.utf8).base64EncodedString()
        let responseData = try await client.firehoseRequest(
            action: "PutRecord",
            payload: [
                "DeliveryStreamName": name,
                "Record": ["Data": base64Data],
            ]
        )
        guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let recordId = json["RecordId"] as? String else {
            throw LocalStackClientError.invalidURL
        }
        return recordId
    }
}
