import Foundation

// MARK: - Table Models

struct DynamoDBTable: Identifiable, Hashable {
    let tableName: String

    var id: String { tableName }
}

struct DynamoDBTableDetail {
    let tableName: String
    let tableStatus: String
    let itemCount: Int
    let tableSizeBytes: Int
    let creationDateTime: Date?
    let keySchema: [KeySchemaElement]
    let attributeDefinitions: [AttributeDefinition]
    let globalSecondaryIndexes: [GlobalSecondaryIndex]
    let localSecondaryIndexes: [LocalSecondaryIndex]
    let billingMode: String
    let provisionedThroughput: ProvisionedThroughput?

    var partitionKey: KeySchemaElement? {
        keySchema.first { $0.keyType == "HASH" }
    }

    var sortKey: KeySchemaElement? {
        keySchema.first { $0.keyType == "RANGE" }
    }

    func attributeType(for name: String) -> String? {
        attributeDefinitions.first { $0.attributeName == name }?.attributeType
    }

    init(from dict: [String: Any]) {
        tableName = dict["TableName"] as? String ?? ""
        tableStatus = dict["TableStatus"] as? String ?? ""
        itemCount = dict["ItemCount"] as? Int ?? 0
        tableSizeBytes = dict["TableSizeBytes"] as? Int ?? 0
        billingMode = (dict["BillingModeSummary"] as? [String: Any])?["BillingMode"] as? String ?? "PAY_PER_REQUEST"

        if let ts = dict["CreationDateTime"] as? Double {
            creationDateTime = Date(timeIntervalSince1970: ts)
        } else {
            creationDateTime = nil
        }

        keySchema = (dict["KeySchema"] as? [[String: Any]] ?? []).map { KeySchemaElement(from: $0) }
        attributeDefinitions = (dict["AttributeDefinitions"] as? [[String: Any]] ?? []).map { AttributeDefinition(from: $0) }
        globalSecondaryIndexes = (dict["GlobalSecondaryIndexes"] as? [[String: Any]] ?? []).map { GlobalSecondaryIndex(from: $0) }
        localSecondaryIndexes = (dict["LocalSecondaryIndexes"] as? [[String: Any]] ?? []).map { LocalSecondaryIndex(from: $0) }

        if let pt = dict["ProvisionedThroughput"] as? [String: Any] {
            provisionedThroughput = ProvisionedThroughput(from: pt)
        } else {
            provisionedThroughput = nil
        }
    }
}

struct KeySchemaElement: Identifiable {
    let attributeName: String
    let keyType: String // HASH or RANGE

    var id: String { "\(attributeName)-\(keyType)" }

    var keyTypeDisplay: String {
        keyType == "HASH" ? "Partition Key" : "Sort Key"
    }

    init(from dict: [String: Any]) {
        attributeName = dict["AttributeName"] as? String ?? ""
        keyType = dict["KeyType"] as? String ?? ""
    }
}

struct AttributeDefinition: Identifiable {
    let attributeName: String
    let attributeType: String // S, N, B

    var id: String { attributeName }

    var typeDisplay: String {
        switch attributeType {
        case "S": "String"
        case "N": "Number"
        case "B": "Binary"
        default: attributeType
        }
    }

    init(from dict: [String: Any]) {
        attributeName = dict["AttributeName"] as? String ?? ""
        attributeType = dict["AttributeType"] as? String ?? ""
    }
}

struct GlobalSecondaryIndex: Identifiable {
    let indexName: String
    let keySchema: [KeySchemaElement]
    let projection: String
    let indexStatus: String

    var id: String { indexName }

    init(from dict: [String: Any]) {
        indexName = dict["IndexName"] as? String ?? ""
        keySchema = (dict["KeySchema"] as? [[String: Any]] ?? []).map { KeySchemaElement(from: $0) }
        projection = (dict["Projection"] as? [String: Any])?["ProjectionType"] as? String ?? "ALL"
        indexStatus = dict["IndexStatus"] as? String ?? ""
    }
}

struct LocalSecondaryIndex: Identifiable {
    let indexName: String
    let keySchema: [KeySchemaElement]
    let projection: String

    var id: String { indexName }

    init(from dict: [String: Any]) {
        indexName = dict["IndexName"] as? String ?? ""
        keySchema = (dict["KeySchema"] as? [[String: Any]] ?? []).map { KeySchemaElement(from: $0) }
        projection = (dict["Projection"] as? [String: Any])?["ProjectionType"] as? String ?? "ALL"
    }
}

struct ProvisionedThroughput {
    let readCapacityUnits: Int
    let writeCapacityUnits: Int

    init(from dict: [String: Any]) {
        readCapacityUnits = dict["ReadCapacityUnits"] as? Int ?? 0
        writeCapacityUnits = dict["WriteCapacityUnits"] as? Int ?? 0
    }
}

// MARK: - AttributeValue

enum AttributeValue: Hashable {
    case string(String)
    case number(String)
    case binary(String)
    case bool(Bool)
    case null
    case list([AttributeValue])
    case map([String: AttributeValue])
    case stringSet([String])
    case numberSet([String])
    case binarySet([String])

    var typeBadge: String {
        switch self {
        case .string: "S"
        case .number: "N"
        case .binary: "B"
        case .bool: "BOOL"
        case .null: "NULL"
        case .list: "L"
        case .map: "M"
        case .stringSet: "SS"
        case .numberSet: "NS"
        case .binarySet: "BS"
        }
    }

    /// Whether this value type supports inline text editing in the grid.
    /// True for string, number, bool. False for complex types (map, list, sets, null, binary).
    var isInlineEditable: Bool {
        switch self {
        case .string, .number, .bool: return true
        default: return false
        }
    }

    var displayString: String {
        switch self {
        case .string(let s): return s
        case .number(let n): return n
        case .binary(let b): return b
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        case .list(let arr):
            let items = arr.map(\.displayString).joined(separator: ", ")
            return "[\(items)]"
        case .map(let dict):
            let items = dict.sorted(by: { $0.key < $1.key })
                .map { "\($0.key): \($0.value.displayString)" }
                .joined(separator: ", ")
            return "{\(items)}"
        case .stringSet(let set): return set.joined(separator: ", ")
        case .numberSet(let set): return set.joined(separator: ", ")
        case .binarySet(let set): return set.joined(separator: ", ")
        }
    }

    /// Convert to DynamoDB JSON format: `{"S": "value"}`, `{"N": "123"}`, etc.
    func toJSON() -> [String: Any] {
        switch self {
        case .string(let s): return ["S": s]
        case .number(let n): return ["N": n]
        case .binary(let b): return ["B": b]
        case .bool(let b): return ["BOOL": b]
        case .null: return ["NULL": true]
        case .list(let arr): return ["L": arr.map { $0.toJSON() }]
        case .map(let dict):
            var result: [String: Any] = [:]
            for (k, v) in dict { result[k] = v.toJSON() }
            return ["M": result]
        case .stringSet(let set): return ["SS": set]
        case .numberSet(let set): return ["NS": set]
        case .binarySet(let set): return ["BS": set]
        }
    }

    /// Parse from DynamoDB JSON format: `{"S": "value"}`, `{"N": "123"}`, etc.
    /// Handles LocalStack quirks: N values may arrive as actual numbers, BOOL as 0/1.
    static func fromJSON(_ dict: [String: Any]) -> AttributeValue? {
        if let s = dict["S"] as? String { return .string(s) }
        if let n = dict["N"] as? String {
            return .number(n)
        } else if let n = dict["N"] as? NSNumber {
            // LocalStack may return N as an actual number instead of a string
            return .number(n.stringValue)
        }
        if let b = dict["B"] as? String { return .binary(b) }
        if let b = dict["BOOL"] as? Bool {
            return .bool(b)
        } else if let b = dict["BOOL"] as? NSNumber {
            return .bool(b.boolValue)
        }
        if dict["NULL"] != nil { return .null }
        if let arr = dict["L"] as? [[String: Any]] {
            return .list(arr.compactMap { fromJSON($0) })
        }
        if let m = dict["M"] as? [String: Any] {
            var result: [String: AttributeValue] = [:]
            for (k, v) in m {
                if let vDict = v as? [String: Any], let val = fromJSON(vDict) {
                    result[k] = val
                }
            }
            return .map(result)
        }
        if let ss = dict["SS"] as? [String] { return .stringSet(ss) }
        if let ns = dict["NS"] as? [String] {
            return .numberSet(ns)
        } else if let ns = dict["NS"] as? [NSNumber] {
            return .numberSet(ns.map(\.stringValue))
        }
        if let bs = dict["BS"] as? [String] { return .binarySet(bs) }
        return nil
    }
}

// MARK: - Item Model

struct DynamoDBItem: Identifiable, Hashable {
    let attributes: [String: AttributeValue]

    /// Stable identity from all attribute values
    var id: String {
        attributes.sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value.displayString)" }
            .joined(separator: "&")
    }

    /// Derive ID from primary key values for stable identity
    func id(keySchema: [KeySchemaElement]) -> String {
        keySchema.map { key in
            attributes[key.attributeName]?.displayString ?? ""
        }.joined(separator: "#")
    }

    /// Convenience to get display value for a key attribute
    func keyValue(for keyName: String) -> String {
        attributes[keyName]?.displayString ?? ""
    }

    /// Non-key attributes preview (first few attributes, truncated)
    func attributesPreview(excluding keyNames: [String], maxCount: Int = 3) -> String {
        let nonKey = attributes
            .filter { !keyNames.contains($0.key) }
            .sorted { $0.key < $1.key }
            .prefix(maxCount)
            .map { "\($0.key)=\($0.value.displayString)" }
            .joined(separator: ", ")
        let remaining = attributes.count - keyNames.count - min(maxCount, attributes.count - keyNames.count)
        if remaining > 0 {
            return nonKey + " (+\(remaining) more)"
        }
        return nonKey
    }

    /// Build the key dict for GetItem/DeleteItem
    func primaryKey(keySchema: [KeySchemaElement]) -> [String: AttributeValue] {
        var key: [String: AttributeValue] = [:]
        for ks in keySchema {
            if let val = attributes[ks.attributeName] {
                key[ks.attributeName] = val
            }
        }
        return key
    }

    /// Convert full item to DynamoDB JSON for PutItem
    func toJSON() -> [String: Any] {
        var result: [String: Any] = [:]
        for (k, v) in attributes {
            result[k] = v.toJSON()
        }
        return result
    }

    /// Parse item from DynamoDB JSON response
    static func fromJSON(_ dict: [String: Any]) -> DynamoDBItem {
        var attrs: [String: AttributeValue] = [:]
        for (key, value) in dict {
            if let typedValue = value as? [String: Any],
               let av = AttributeValue.fromJSON(typedValue) {
                attrs[key] = av
            }
        }
        return DynamoDBItem(attributes: attrs)
    }

    /// Convert to standard JSON (not DynamoDB typed JSON) for display
    func toDisplayJSON() -> String {
        var result: [String: Any] = [:]
        for (k, v) in attributes.sorted(by: { $0.key < $1.key }) {
            result[k] = v.toJSON()
        }
        guard let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }
}

// MARK: - Scan/Query Result

struct ScanResult {
    let items: [DynamoDBItem]
    let count: Int
    let scannedCount: Int
    let lastEvaluatedKey: [String: Any]?

    var hasMorePages: Bool { lastEvaluatedKey != nil }

    init(from dict: [String: Any]) {
        count = dict["Count"] as? Int ?? 0
        scannedCount = dict["ScannedCount"] as? Int ?? 0

        if let itemDicts = dict["Items"] as? [[String: Any]] {
            items = itemDicts.map { DynamoDBItem.fromJSON($0) }
        } else {
            items = []
        }

        lastEvaluatedKey = dict["LastEvaluatedKey"] as? [String: Any]
    }
}

// MARK: - CLI Helpers

extension DynamoDBTable {
    private static func shellEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "'\\''")
    }

    func describeTableCLI(endpointUrl: String, region: String) -> String {
        [
            "aws dynamodb describe-table \\",
            "  --table-name '\(Self.shellEscape(tableName))' \\",
            "  --endpoint-url \(endpointUrl) \\",
            "  --region \(region)",
        ].joined(separator: "\n")
    }

    func scanTableCLI(endpointUrl: String, region: String) -> String {
        [
            "aws dynamodb scan \\",
            "  --table-name '\(Self.shellEscape(tableName))' \\",
            "  --endpoint-url \(endpointUrl) \\",
            "  --region \(region)",
        ].joined(separator: "\n")
    }

    func deleteTableCLI(endpointUrl: String, region: String) -> String {
        [
            "aws dynamodb delete-table \\",
            "  --table-name '\(Self.shellEscape(tableName))' \\",
            "  --endpoint-url \(endpointUrl) \\",
            "  --region \(region)",
        ].joined(separator: "\n")
    }
}

extension DynamoDBItem {
    private static func shellEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "'\\''")
    }

    func putItemCLI(tableName: String, endpointUrl: String, region: String) -> String {
        let json = toDisplayJSON()
        return [
            "aws dynamodb put-item \\",
            "  --table-name '\(Self.shellEscape(tableName))' \\",
            "  --item '\(Self.shellEscape(json))' \\",
            "  --endpoint-url \(endpointUrl) \\",
            "  --region \(region)",
        ].joined(separator: "\n")
    }

    func getItemCLI(tableName: String, keySchema: [KeySchemaElement], endpointUrl: String, region: String) -> String {
        let keyDict = primaryKey(keySchema: keySchema)
        var jsonDict: [String: Any] = [:]
        for (k, v) in keyDict { jsonDict[k] = v.toJSON() }
        let json: String
        if let data = try? JSONSerialization.data(withJSONObject: jsonDict, options: [.sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            json = str
        } else {
            json = "{}"
        }
        return [
            "aws dynamodb get-item \\",
            "  --table-name '\(Self.shellEscape(tableName))' \\",
            "  --key '\(Self.shellEscape(json))' \\",
            "  --endpoint-url \(endpointUrl) \\",
            "  --region \(region)",
        ].joined(separator: "\n")
    }
}
