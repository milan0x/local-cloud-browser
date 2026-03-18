import Foundation

final class KinesisFirehoseService: BaseService {
    // MARK: - Delivery Stream Operations

    func listDeliveryStreamsPage(token: String? = nil) async throws -> ([FirehoseDeliveryStreamSummary], String?) {
        var payload: [String: Any] = [:]
        if let token {
            payload["ExclusiveStartDeliveryStreamName"] = token
        }
        let data = try await client.firehoseRequest(action: "ListDeliveryStreams", payload: payload)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ([], nil)
        }
        let names = json["DeliveryStreamNames"] as? [String] ?? []
        let hasMore = json["HasMoreDeliveryStreams"] as? Bool ?? false

        // ListDeliveryStreams only returns names — describe each concurrently for summary info
        let streams: [FirehoseDeliveryStreamSummary] = await withTaskGroup(of: (Int, FirehoseDeliveryStreamSummary).self) { group in
            let maxConcurrency = 10
            var index = 0
            var results: [(Int, FirehoseDeliveryStreamSummary)] = []

            for name in names {
                let i = index
                if i >= maxConcurrency {
                    if let result = await group.next() {
                        results.append(result)
                    }
                }
                group.addTask {
                    do {
                        let detail = try await self.describeDeliveryStream(name: name)
                        return (i, FirehoseDeliveryStreamSummary(
                            deliveryStreamName: detail.deliveryStreamName,
                            deliveryStreamARN: detail.deliveryStreamARN,
                            deliveryStreamStatus: detail.deliveryStreamStatus,
                            deliveryStreamType: detail.deliveryStreamType,
                            createTimestamp: detail.createTimestamp
                        ))
                    } catch {
                        return (i, FirehoseDeliveryStreamSummary(deliveryStreamName: name))
                    }
                }
                index += 1
            }
            for await result in group {
                results.append(result)
            }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }

        let nextToken = hasMore ? names.last : nil
        return (streams, nextToken)
    }

    func listDeliveryStreams() async throws -> [FirehoseDeliveryStreamSummary] {
        var allStreams: [FirehoseDeliveryStreamSummary] = []
        var nextToken: String? = nil

        repeat {
            let (streams, token) = try await listDeliveryStreamsPage(token: nextToken)
            allStreams.append(contentsOf: streams)
            nextToken = token
            if allStreams.count >= 10_000 { break }
        } while nextToken != nil

        return allStreams
    }

    func describeDeliveryStream(name: String) async throws -> FirehoseDeliveryStreamDetail {
        let data = try await client.firehoseRequest(
            action: "DescribeDeliveryStream",
            payload: ["DeliveryStreamName": name]
        )
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let desc = json["DeliveryStreamDescription"] as? [String: Any] else {
            throw CloudClientError.invalidURL
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
            throw CloudClientError.invalidURL
        }
        return recordId
    }
}
