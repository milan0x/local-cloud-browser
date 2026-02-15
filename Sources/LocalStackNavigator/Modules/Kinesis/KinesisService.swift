import Foundation

@MainActor
final class KinesisService: ObservableObject {
    private var client: LocalStackClient!

    func updateClient(_ newClient: LocalStackClient) {
        self.client = newClient
    }

    // MARK: - Stream Operations

    func listStreams() async throws -> [KinesisStreamSummary] {
        var allStreams: [KinesisStreamSummary] = []
        var hasMore = true
        var exclusiveStartName: String?

        while hasMore {
            var payload: [String: Any] = [:]
            if let startName = exclusiveStartName {
                payload["ExclusiveStartStreamName"] = startName
            }
            let data = try await client.kinesisRequest(action: "ListStreams", payload: payload)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                break
            }

            // AWS may return StreamSummaries (newer API) or StreamNames (older/LocalStack)
            if let summaries = json["StreamSummaries"] as? [[String: Any]] {
                allStreams.append(contentsOf: summaries.map { KinesisStreamSummary(from: $0) })
            } else if let names = json["StreamNames"] as? [String] {
                // Enrich each name with DescribeStreamSummary
                for name in names {
                    do {
                        let detail = try await describeStreamSummary(name: name)
                        allStreams.append(KinesisStreamSummary(
                            streamName: detail.streamName,
                            streamARN: detail.streamARN,
                            streamStatus: detail.streamStatus,
                            streamMode: detail.streamMode,
                            creationTimestamp: detail.creationTimestamp
                        ))
                    } catch {
                        allStreams.append(KinesisStreamSummary(streamName: name))
                    }
                }
            }

            hasMore = json["HasMoreStreams"] as? Bool ?? false
            exclusiveStartName = allStreams.last?.streamName
        }

        return allStreams
    }

    func describeStreamSummary(name: String) async throws -> KinesisStreamDetail {
        let data = try await client.kinesisRequest(
            action: "DescribeStreamSummary",
            payload: ["StreamName": name]
        )
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let summary = json["StreamDescriptionSummary"] as? [String: Any] else {
            throw LocalStackClientError.invalidURL
        }
        return KinesisStreamDetail(from: summary)
    }

    func createStream(name: String, shardCount: Int, mode: String) async throws {
        var payload: [String: Any] = ["StreamName": name]
        if mode == "ON_DEMAND" {
            payload["StreamModeDetails"] = ["StreamMode": "ON_DEMAND"]
        } else {
            payload["ShardCount"] = shardCount
        }
        _ = try await client.kinesisRequest(action: "CreateStream", payload: payload)
    }

    func deleteStream(name: String) async throws {
        _ = try await client.kinesisRequest(
            action: "DeleteStream",
            payload: [
                "StreamName": name,
                "EnforceConsumerDeletion": true,
            ]
        )
    }

    // MARK: - Shard Operations

    func listShards(name: String) async throws -> [KinesisShard] {
        var allShards: [KinesisShard] = []
        var nextToken: String?

        repeat {
            var payload: [String: Any] = ["StreamName": name]
            if let token = nextToken {
                payload["NextToken"] = token
            }
            let data = try await client.kinesisRequest(action: "ListShards", payload: payload)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                break
            }
            if let shards = json["Shards"] as? [[String: Any]] {
                allShards.append(contentsOf: shards.map { KinesisShard(from: $0) })
            }
            nextToken = json["NextToken"] as? String
        } while nextToken != nil

        return allShards
    }

    func getShardIterator(name: String, shardId: String, type: String = "TRIM_HORIZON") async throws -> String {
        let data = try await client.kinesisRequest(
            action: "GetShardIterator",
            payload: [
                "StreamName": name,
                "ShardId": shardId,
                "ShardIteratorType": type,
            ]
        )
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let iterator = json["ShardIterator"] as? String else {
            throw LocalStackClientError.invalidURL
        }
        return iterator
    }

    func getRecords(iterator: String) async throws -> ([KinesisRecord], String?) {
        let data = try await client.kinesisRequest(
            action: "GetRecords",
            payload: ["ShardIterator": iterator]
        )
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ([], nil)
        }
        let records = (json["Records"] as? [[String: Any]] ?? []).map { KinesisRecord(from: $0) }
        let nextIterator = json["NextShardIterator"] as? String
        // Only return nextIterator if there are records or the shard is still open
        let effectiveNext = records.isEmpty ? nil : nextIterator
        return (records, effectiveNext)
    }

    // MARK: - Put Record

    func putRecord(name: String, partitionKey: String, data: String) async throws -> String {
        let base64Data = Data(data.utf8).base64EncodedString()
        let responseData = try await client.kinesisRequest(
            action: "PutRecord",
            payload: [
                "StreamName": name,
                "PartitionKey": partitionKey,
                "Data": base64Data,
            ]
        )
        guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let seqNum = json["SequenceNumber"] as? String else {
            throw LocalStackClientError.invalidURL
        }
        return seqNum
    }
}
