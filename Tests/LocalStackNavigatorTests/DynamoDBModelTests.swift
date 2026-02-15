import Testing
import Foundation
@testable import LocalStackNavigator

@Suite("DynamoDB Models")
struct DynamoDBModelTests {

    // MARK: - AttributeValue.typeBadge

    @Test("typeBadge returns correct badges for all types")
    func typeBadges() {
        #expect(AttributeValue.string("x").typeBadge == "S")
        #expect(AttributeValue.number("1").typeBadge == "N")
        #expect(AttributeValue.binary("b").typeBadge == "B")
        #expect(AttributeValue.bool(true).typeBadge == "BOOL")
        #expect(AttributeValue.null.typeBadge == "NULL")
        #expect(AttributeValue.list([]).typeBadge == "L")
        #expect(AttributeValue.map([:]).typeBadge == "M")
        #expect(AttributeValue.stringSet([]).typeBadge == "SS")
        #expect(AttributeValue.numberSet([]).typeBadge == "NS")
        #expect(AttributeValue.binarySet([]).typeBadge == "BS")
    }

    // MARK: - AttributeValue.isInlineEditable

    @Test("isInlineEditable true for string, number, bool")
    func inlineEditableTrue() {
        #expect(AttributeValue.string("x").isInlineEditable == true)
        #expect(AttributeValue.number("1").isInlineEditable == true)
        #expect(AttributeValue.bool(true).isInlineEditable == true)
    }

    @Test("isInlineEditable false for complex types")
    func inlineEditableFalse() {
        #expect(AttributeValue.null.isInlineEditable == false)
        #expect(AttributeValue.list([]).isInlineEditable == false)
        #expect(AttributeValue.map([:]).isInlineEditable == false)
        #expect(AttributeValue.stringSet([]).isInlineEditable == false)
        #expect(AttributeValue.numberSet([]).isInlineEditable == false)
        #expect(AttributeValue.binarySet([]).isInlineEditable == false)
        #expect(AttributeValue.binary("b").isInlineEditable == false)
    }

    // MARK: - AttributeValue.displayString

    @Test("displayString for scalar types")
    func displayStringScalar() {
        #expect(AttributeValue.string("hello").displayString == "hello")
        #expect(AttributeValue.number("42").displayString == "42")
        #expect(AttributeValue.binary("data").displayString == "data")
        #expect(AttributeValue.bool(true).displayString == "true")
        #expect(AttributeValue.bool(false).displayString == "false")
        #expect(AttributeValue.null.displayString == "null")
    }

    @Test("displayString for list")
    func displayStringList() {
        let list = AttributeValue.list([.string("a"), .number("1")])
        #expect(list.displayString == "[a, 1]")
    }

    @Test("displayString for map")
    func displayStringMap() {
        let map = AttributeValue.map(["key": .string("val")])
        #expect(map.displayString == "{key: val}")
    }

    @Test("displayString for sets")
    func displayStringSets() {
        #expect(AttributeValue.stringSet(["a", "b"]).displayString == "a, b")
        #expect(AttributeValue.numberSet(["1", "2"]).displayString == "1, 2")
        #expect(AttributeValue.binarySet(["x"]).displayString == "x")
    }

    // MARK: - AttributeValue.toJSON

    @Test("toJSON for scalar types")
    func toJSONScalar() {
        let sj = AttributeValue.string("hello").toJSON()
        #expect(sj["S"] as? String == "hello")

        let nj = AttributeValue.number("42").toJSON()
        #expect(nj["N"] as? String == "42")

        let bj = AttributeValue.bool(true).toJSON()
        #expect(bj["BOOL"] as? Bool == true)

        let nullj = AttributeValue.null.toJSON()
        #expect(nullj["NULL"] as? Bool == true)
    }

    @Test("toJSON for list")
    func toJSONList() {
        let list = AttributeValue.list([.string("a")])
        let json = list.toJSON()
        let arr = json["L"] as? [[String: Any]]
        #expect(arr?.count == 1)
    }

    @Test("toJSON for sets")
    func toJSONSets() {
        let ss = AttributeValue.stringSet(["a", "b"]).toJSON()
        #expect((ss["SS"] as? [String])?.count == 2)

        let ns = AttributeValue.numberSet(["1"]).toJSON()
        #expect((ns["NS"] as? [String])?.count == 1)
    }

    // MARK: - AttributeValue.fromJSON

    @Test("fromJSON parses string")
    func fromJSONString() {
        let av = AttributeValue.fromJSON(["S": "hello"])
        #expect(av == .string("hello"))
    }

    @Test("fromJSON parses number as string")
    func fromJSONNumber() {
        let av = AttributeValue.fromJSON(["N": "42"])
        #expect(av == .number("42"))
    }

    @Test("fromJSON parses number as NSNumber")
    func fromJSONNumberNSNumber() {
        let av = AttributeValue.fromJSON(["N": NSNumber(value: 42)])
        #expect(av == .number("42"))
    }

    @Test("fromJSON parses bool")
    func fromJSONBool() {
        #expect(AttributeValue.fromJSON(["BOOL": true]) == .bool(true))
        #expect(AttributeValue.fromJSON(["BOOL": false]) == .bool(false))
    }

    @Test("fromJSON parses null")
    func fromJSONNull() {
        #expect(AttributeValue.fromJSON(["NULL": true]) == .null)
    }

    @Test("fromJSON parses list")
    func fromJSONList() {
        let av = AttributeValue.fromJSON(["L": [["S": "a"], ["N": "1"]]])
        #expect(av == .list([.string("a"), .number("1")]))
    }

    @Test("fromJSON parses map")
    func fromJSONMap() {
        let av = AttributeValue.fromJSON(["M": ["k": ["S": "v"]]])
        #expect(av == .map(["k": .string("v")]))
    }

    @Test("fromJSON parses string set")
    func fromJSONStringSet() {
        let av = AttributeValue.fromJSON(["SS": ["a", "b"]])
        #expect(av == .stringSet(["a", "b"]))
    }

    @Test("fromJSON returns nil for empty dict")
    func fromJSONNil() {
        #expect(AttributeValue.fromJSON([:]) == nil)
    }

    // MARK: - DynamoDBItem

    @Test("DynamoDBItem.fromJSON parses item")
    func itemFromJSON() {
        let dict: [String: Any] = [
            "id": ["S": "abc"],
            "count": ["N": "5"],
        ]
        let item = DynamoDBItem.fromJSON(dict)
        #expect(item.attributes["id"] == .string("abc"))
        #expect(item.attributes["count"] == .number("5"))
    }

    @Test("DynamoDBItem.keyValue returns display string")
    func itemKeyValue() {
        let item = DynamoDBItem(attributes: ["pk": .string("hello")])
        #expect(item.keyValue(for: "pk") == "hello")
        #expect(item.keyValue(for: "missing") == "")
    }

    @Test("DynamoDBItem.attributesPreview shows non-key attributes")
    func itemAttributesPreview() {
        let item = DynamoDBItem(attributes: [
            "pk": .string("key1"),
            "name": .string("Alice"),
            "age": .number("30"),
        ])
        let preview = item.attributesPreview(excluding: ["pk"])
        #expect(preview.contains("age=30"))
        #expect(preview.contains("name=Alice"))
    }

    @Test("DynamoDBItem.primaryKey extracts key attributes")
    func itemPrimaryKey() {
        let item = DynamoDBItem(attributes: [
            "pk": .string("key1"),
            "sk": .string("sort1"),
            "data": .string("value"),
        ])
        let ks = [
            KeySchemaElement(from: ["AttributeName": "pk", "KeyType": "HASH"]),
            KeySchemaElement(from: ["AttributeName": "sk", "KeyType": "RANGE"]),
        ]
        let pk = item.primaryKey(keySchema: ks)
        #expect(pk.count == 2)
        #expect(pk["pk"] == .string("key1"))
        #expect(pk["sk"] == .string("sort1"))
    }

    // MARK: - DynamoDBTableDetail

    @Test("partitionKey and sortKey")
    func tableDetailKeys() {
        let detail = DynamoDBTableDetail(from: [
            "TableName": "test",
            "KeySchema": [
                ["AttributeName": "pk", "KeyType": "HASH"],
                ["AttributeName": "sk", "KeyType": "RANGE"],
            ],
        ])
        #expect(detail.partitionKey?.attributeName == "pk")
        #expect(detail.sortKey?.attributeName == "sk")
    }

    @Test("attributeType returns type for known attribute")
    func tableDetailAttributeType() {
        let detail = DynamoDBTableDetail(from: [
            "TableName": "test",
            "AttributeDefinitions": [
                ["AttributeName": "pk", "AttributeType": "S"],
                ["AttributeName": "count", "AttributeType": "N"],
            ],
        ])
        #expect(detail.attributeType(for: "pk") == "S")
        #expect(detail.attributeType(for: "count") == "N")
        #expect(detail.attributeType(for: "missing") == nil)
    }

    // MARK: - KeySchemaElement

    @Test("keyTypeDisplay maps HASH and RANGE")
    func keyTypeDisplay() {
        let hash = KeySchemaElement(from: ["AttributeName": "pk", "KeyType": "HASH"])
        #expect(hash.keyTypeDisplay == "Partition Key")

        let range = KeySchemaElement(from: ["AttributeName": "sk", "KeyType": "RANGE"])
        #expect(range.keyTypeDisplay == "Sort Key")
    }

    // MARK: - AttributeDefinition

    @Test("typeDisplay maps S, N, B")
    func attrDefTypeDisplay() {
        #expect(AttributeDefinition(from: ["AttributeName": "a", "AttributeType": "S"]).typeDisplay == "String")
        #expect(AttributeDefinition(from: ["AttributeName": "a", "AttributeType": "N"]).typeDisplay == "Number")
        #expect(AttributeDefinition(from: ["AttributeName": "a", "AttributeType": "B"]).typeDisplay == "Binary")
        #expect(AttributeDefinition(from: ["AttributeName": "a", "AttributeType": "X"]).typeDisplay == "X")
    }

    // MARK: - CLI

    @Test("describeTableCLI generates valid command")
    func describeTableCLI() {
        let table = DynamoDBTable(tableName: "my-table")
        let cli = table.describeTableCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws dynamodb describe-table"))
        #expect(cli.contains("my-table"))
    }

    @Test("scanTableCLI generates valid command")
    func scanTableCLI() {
        let table = DynamoDBTable(tableName: "my-table")
        let cli = table.scanTableCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws dynamodb scan"))
        #expect(cli.contains("my-table"))
    }

    @Test("deleteTableCLI generates valid command")
    func deleteTableCLI() {
        let table = DynamoDBTable(tableName: "my-table")
        let cli = table.deleteTableCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws dynamodb delete-table"))
    }

    // MARK: - ScanResult

    @Test("ScanResult.hasMorePages")
    func scanResultHasMore() {
        let withKey = ScanResult(from: ["Count": 1, "ScannedCount": 1, "LastEvaluatedKey": ["pk": ["S": "x"]]])
        #expect(withKey.hasMorePages == true)

        let noKey = ScanResult(from: ["Count": 1, "ScannedCount": 1])
        #expect(noKey.hasMorePages == false)
    }
}
