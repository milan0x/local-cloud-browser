import Foundation

final class DynamoDBService: LocalStackService {
    // MARK: - Table Operations

    func listTables(region: String? = nil) async throws -> [DynamoDBTable] {
        let data = try await client.dynamodbRequest(action: "ListTables", region: region)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tableNames = json["TableNames"] as? [String] else {
            return []
        }
        return tableNames.map { DynamoDBTable(tableName: $0) }
    }

    func describeTable(tableName: String) async throws -> DynamoDBTableDetail {
        let data = try await client.dynamodbRequest(
            action: "DescribeTable",
            payload: ["TableName": tableName]
        )
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let table = json["Table"] as? [String: Any] else {
            throw LocalStackClientError.invalidURL
        }
        return DynamoDBTableDetail(from: table)
    }

    func createTable(
        tableName: String,
        partitionKeyName: String,
        partitionKeyType: String,
        sortKeyName: String?,
        sortKeyType: String?,
        streamEnabled: Bool = false,
        streamViewType: String? = nil
    ) async throws {
        var keySchema: [[String: String]] = [
            ["AttributeName": partitionKeyName, "KeyType": "HASH"],
        ]
        var attributeDefinitions: [[String: String]] = [
            ["AttributeName": partitionKeyName, "AttributeType": partitionKeyType],
        ]

        if let skName = sortKeyName, !skName.isEmpty, let skType = sortKeyType {
            keySchema.append(["AttributeName": skName, "KeyType": "RANGE"])
            attributeDefinitions.append(["AttributeName": skName, "AttributeType": skType])
        }

        var payload: [String: Any] = [
            "TableName": tableName,
            "KeySchema": keySchema,
            "AttributeDefinitions": attributeDefinitions,
            "BillingMode": "PAY_PER_REQUEST",
        ]

        if streamEnabled, let viewType = streamViewType {
            payload["StreamSpecification"] = [
                "StreamEnabled": true,
                "StreamViewType": viewType,
            ] as [String: Any]
        }

        _ = try await client.dynamodbRequest(action: "CreateTable", payload: payload)
    }

    func deleteTable(tableName: String) async throws {
        _ = try await client.dynamodbRequest(
            action: "DeleteTable",
            payload: ["TableName": tableName]
        )
    }

    // MARK: - Item Operations

    func scan(
        tableName: String,
        limit: Int = 50,
        exclusiveStartKey: [String: Any]? = nil,
        filterExpression: String? = nil,
        expressionAttributeValues: [String: Any]? = nil,
        expressionAttributeNames: [String: String]? = nil
    ) async throws -> ScanResult {
        var payload: [String: Any] = [
            "TableName": tableName,
            "Limit": limit,
        ]
        if let startKey = exclusiveStartKey {
            payload["ExclusiveStartKey"] = startKey
        }
        if let filter = filterExpression, !filter.isEmpty {
            payload["FilterExpression"] = filter
        }
        if let values = expressionAttributeValues, !values.isEmpty {
            payload["ExpressionAttributeValues"] = values
        }
        if let names = expressionAttributeNames, !names.isEmpty {
            payload["ExpressionAttributeNames"] = names
        }

        let data = try await client.dynamodbRequest(action: "Scan", payload: payload)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ScanResult(from: [:])
        }
        return ScanResult(from: json)
    }

    func query(
        tableName: String,
        keyConditionExpression: String,
        expressionAttributeValues: [String: Any],
        expressionAttributeNames: [String: String]? = nil,
        indexName: String? = nil,
        limit: Int = 50,
        exclusiveStartKey: [String: Any]? = nil,
        filterExpression: String? = nil
    ) async throws -> ScanResult {
        var payload: [String: Any] = [
            "TableName": tableName,
            "KeyConditionExpression": keyConditionExpression,
            "ExpressionAttributeValues": expressionAttributeValues,
            "Limit": limit,
        ]
        if let names = expressionAttributeNames, !names.isEmpty {
            payload["ExpressionAttributeNames"] = names
        }
        if let idx = indexName {
            payload["IndexName"] = idx
        }
        if let startKey = exclusiveStartKey {
            payload["ExclusiveStartKey"] = startKey
        }
        if let filter = filterExpression, !filter.isEmpty {
            payload["FilterExpression"] = filter
        }

        let data = try await client.dynamodbRequest(action: "Query", payload: payload)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ScanResult(from: [:])
        }
        return ScanResult(from: json)
    }

    func putItem(tableName: String, item: [String: AttributeValue]) async throws {
        var itemJSON: [String: Any] = [:]
        for (k, v) in item {
            itemJSON[k] = v.toJSON()
        }
        let payload: [String: Any] = [
            "TableName": tableName,
            "Item": itemJSON,
        ]
        _ = try await client.dynamodbRequest(action: "PutItem", payload: payload)
    }

    // MARK: - Stream Operations

    func listStreams(tableName: String) async throws -> [DynamoDBStream] {
        let data = try await client.dynamodbStreamsRequest(
            action: "ListStreams",
            payload: ["TableName": tableName]
        )
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let streams = json["Streams"] as? [[String: Any]] else {
            return []
        }
        return streams.map { DynamoDBStream(from: $0) }
    }

    func describeStream(streamArn: String) async throws -> DynamoDBStreamDescription {
        let data = try await client.dynamodbStreamsRequest(
            action: "DescribeStream",
            payload: ["StreamArn": streamArn]
        )
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let desc = json["StreamDescription"] as? [String: Any] else {
            throw LocalStackClientError.invalidURL
        }
        return DynamoDBStreamDescription(from: desc)
    }

    func getShardIterator(streamArn: String, shardId: String, type: String = "TRIM_HORIZON") async throws -> String {
        let data = try await client.dynamodbStreamsRequest(
            action: "GetShardIterator",
            payload: [
                "StreamArn": streamArn,
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

    func getRecords(shardIterator: String, limit: Int = 100) async throws -> ([DynamoDBStreamRecord], nextIterator: String?) {
        let data = try await client.dynamodbStreamsRequest(
            action: "GetRecords",
            payload: [
                "ShardIterator": shardIterator,
                "Limit": limit,
            ]
        )
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ([], nextIterator: nil)
        }
        let records = (json["Records"] as? [[String: Any]] ?? []).map { DynamoDBStreamRecord(from: $0) }
        let nextIterator = json["NextShardIterator"] as? String
        return (records, nextIterator: nextIterator)
    }

    func deleteItem(tableName: String, key: [String: AttributeValue]) async throws {
        var keyJSON: [String: Any] = [:]
        for (k, v) in key {
            keyJSON[k] = v.toJSON()
        }
        let payload: [String: Any] = [
            "TableName": tableName,
            "Key": keyJSON,
        ]
        _ = try await client.dynamodbRequest(action: "DeleteItem", payload: payload)
    }
}
