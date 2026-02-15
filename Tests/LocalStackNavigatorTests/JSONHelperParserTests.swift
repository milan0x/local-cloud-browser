import Testing
import Foundation
@testable import LocalStackNavigator

@Suite("JSONHelperParser")
struct JSONHelperParserTests {

    // MARK: - parse (Helper → JSON)

    @Test("Parses key-value pairs into JSON object")
    func simpleKeyValue() {
        let input = """
            name "John"
            age 30
            active true
            """
        let result = JSONHelperParser.parse(input)
        #expect(result.error == nil)
        #expect(result.json.contains("\"name\": \"John\""))
        #expect(result.json.contains("\"age\": 30"))
        #expect(result.json.contains("\"active\": true"))
    }

    @Test("Parses nested objects")
    func nestedObject() {
        let input = """
            address
                city "New York"
                zip "10001"
            """
        let result = JSONHelperParser.parse(input)
        #expect(result.error == nil)
        #expect(result.json.contains("\"address\""))
        #expect(result.json.contains("\"city\": \"New York\""))
    }

    @Test("Parses arrays")
    func arrays() {
        let input = """
            tags
                - "swift"
                - "macos"
            """
        let result = JSONHelperParser.parse(input)
        #expect(result.error == nil)
        #expect(result.json.contains("\"tags\""))
        #expect(result.json.contains("\"swift\""))
        #expect(result.json.contains("\"macos\""))
    }

    @Test("Parses null values")
    func nullValue() {
        let input = "middle_name null"
        let result = JSONHelperParser.parse(input)
        #expect(result.error == nil)
        #expect(result.json.contains("null"))
    }

    @Test("Parses boolean values")
    func booleans() {
        let input = """
            enabled true
            deleted false
            """
        let result = JSONHelperParser.parse(input)
        #expect(result.error == nil)
        #expect(result.json.contains("true"))
        #expect(result.json.contains("false"))
    }

    @Test("Parses negative numbers")
    func negativeNumbers() {
        let input = "offset -10"
        let result = JSONHelperParser.parse(input)
        #expect(result.error == nil)
        #expect(result.json.contains("-10"))
    }

    @Test("Parses decimal numbers")
    func decimalNumbers() {
        let input = "price 9.99"
        let result = JSONHelperParser.parse(input)
        #expect(result.error == nil)
        #expect(result.json.contains("9.99"))
    }

    @Test("Empty input returns empty string")
    func emptyInput() {
        let result = JSONHelperParser.parse("")
        #expect(result.json == "")
        #expect(result.error == nil)
    }

    @Test("Reports error for unterminated string")
    func unterminatedString() {
        let input = "name \"unterminated"
        let result = JSONHelperParser.parse(input)
        #expect(result.error != nil)
        #expect(result.error!.contains("unterminated"))
    }

    @Test("Reports error for invalid value")
    func invalidValue() {
        let input = "name not_a_valid_value"
        let result = JSONHelperParser.parse(input)
        #expect(result.error != nil)
        #expect(result.error!.contains("invalid value"))
    }

    @Test("Handles escaped quotes in strings")
    func escapedQuotes() {
        let input = "say \"hello \\\"world\\\"\""
        let result = JSONHelperParser.parse(input)
        #expect(result.error == nil)
        #expect(result.json.contains("hello \\\"world\\\""))
    }

    @Test("Default example parses without error")
    func defaultExample() {
        let result = JSONHelperParser.parse(JSONHelperParser.defaultExample)
        #expect(result.error == nil)
        #expect(!result.json.isEmpty)
    }

    // MARK: - fromJSON (JSON → Helper)

    @Test("Converts simple JSON to helper format")
    func fromJSONSimple() {
        let json = "{\"name\": \"John\", \"age\": 30}"
        let helper = JSONHelperParser.fromJSON(json)
        #expect(helper != nil)
        #expect(helper!.contains("name \"John\""))
        #expect(helper!.contains("age 30"))
    }

    @Test("Converts nested JSON to helper format")
    func fromJSONNested() {
        let json = "{\"address\": {\"city\": \"NYC\"}}"
        let helper = JSONHelperParser.fromJSON(json)
        #expect(helper != nil)
        #expect(helper!.contains("address"))
        #expect(helper!.contains("city \"NYC\""))
    }

    @Test("Converts JSON arrays to helper format")
    func fromJSONArray() {
        let json = "{\"tags\": [\"a\", \"b\"]}"
        let helper = JSONHelperParser.fromJSON(json)
        #expect(helper != nil)
        #expect(helper!.contains("- \"a\""))
        #expect(helper!.contains("- \"b\""))
    }

    @Test("Returns nil for non-object JSON")
    func fromJSONNonObject() {
        #expect(JSONHelperParser.fromJSON("[1, 2, 3]") == nil)
        #expect(JSONHelperParser.fromJSON("\"just a string\"") == nil)
    }

    @Test("Returns nil for empty input")
    func fromJSONEmpty() {
        #expect(JSONHelperParser.fromJSON("") == nil)
    }

    @Test("Returns nil for invalid JSON")
    func fromJSONInvalid() {
        #expect(JSONHelperParser.fromJSON("not json at all") == nil)
    }

    // MARK: - Round-trip

    @Test("Round-trip: helper → JSON → helper preserves structure")
    func roundTrip() {
        let input = """
            name "Alice"
            age 25
            active true
            """
        let jsonResult = JSONHelperParser.parse(input)
        #expect(jsonResult.error == nil)
        let backToHelper = JSONHelperParser.fromJSON(jsonResult.json)
        #expect(backToHelper != nil)
        #expect(backToHelper!.contains("name \"Alice\""))
        #expect(backToHelper!.contains("age 25"))
        #expect(backToHelper!.contains("active true"))
    }
}
