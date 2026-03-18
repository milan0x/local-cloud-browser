import Foundation

final class KinesisService: BaseService {
    // MARK: - Stream Operations

    func listStreamsPage(region: String? = nil, token: String? = nil) async throws -> ([KinesisStreamSummary], String?) {
        var payload: [String: Any] = [:]
        if let token {
            payload["ExclusiveStartStreamName"] = token
        }
        let data = try await client.kinesisRequest(action: "ListStreams", payload: payload, region: region)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ([], nil)
        }

        var streams: [KinesisStreamSummary] = []

        // AWS may return StreamSummaries (newer API) or StreamNames (older API)
        if let summaries = json["StreamSummaries"] as? [[String: Any]] {
            streams.append(contentsOf: summaries.map { KinesisStreamSummary(from: $0) })
        } else if let names = json["StreamNames"] as? [String] {
            // Enrich each name with DescribeStreamSummary
            for name in names {
                do {
                    let detail = try await describeStreamSummary(name: name)
                    streams.append(KinesisStreamSummary(
                        streamName: detail.streamName,
                        streamARN: detail.streamARN,
                        streamStatus: detail.streamStatus,
                        streamMode: detail.streamMode,
                        creationTimestamp: detail.creationTimestamp
                    ))
                } catch {
                    streams.append(KinesisStreamSummary(streamName: name))
                }
            }
        }

        let hasMore = json["HasMoreStreams"] as? Bool ?? false
        let nextToken = hasMore ? streams.last?.streamName : nil
        return (streams, nextToken)
    }

    func listStreams(region: String? = nil) async throws -> [KinesisStreamSummary] {
        var allStreams: [KinesisStreamSummary] = []
        var nextToken: String? = nil

        repeat {
            let (streams, token) = try await listStreamsPage(region: region, token: nextToken)
            allStreams.append(contentsOf: streams)
            nextToken = token
            if allStreams.count >= 10_000 { break }
        } while nextToken != nil

        return allStreams
    }

    func describeStreamSummary(name: String) async throws -> KinesisStreamDetail {
        let data = try await client.kinesisRequest(
            action: "DescribeStreamSummary",
            payload: ["StreamName": name]
        )
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let summary = json["StreamDescriptionSummary"] as? [String: Any] else {
            throw CloudClientError.invalidURL
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

    func listShardsPage(name: String, token: String? = nil) async throws -> ([KinesisShard], String?) {
        var payload: [String: Any] = ["StreamName": name]
        if let token {
            payload["NextToken"] = token
        }
        let data = try await client.kinesisRequest(action: "ListShards", payload: payload)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ([], nil)
        }
        let shards = (json["Shards"] as? [[String: Any]] ?? []).map { KinesisShard(from: $0) }
        return (shards, json["NextToken"] as? String)
    }

    func listShards(name: String) async throws -> [KinesisShard] {
        var allShards: [KinesisShard] = []
        var nextToken: String?

        repeat {
            let (shards, token) = try await listShardsPage(name: name, token: nextToken)
            allShards.append(contentsOf: shards)
            nextToken = token
            if allShards.count >= 10_000 { break }
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
            throw CloudClientError.invalidURL
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
        return (records, nextIterator)
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
            throw CloudClientError.invalidURL
        }
        return seqNum
    }
}
