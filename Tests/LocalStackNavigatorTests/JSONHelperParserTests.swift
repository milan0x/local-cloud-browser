import Testing
import Foundation
@testable import LocalStackNavigator

@Suite("JSONHelperParser")
struct JSONHelperParserTests {

    // MARK: - parse (Helper → JSON)

    @Test("Parses key-value pairs into JSON object")
    func simpleKeyValue() {
        let input = """
            name: John
            age: 30
            active: true
            """
        let result = JSONHelperParser.parse(input)
        #expect(result.error == nil)
        #expect(result.json.contains("\"name\": \"John\""))
        #expect(result.json.contains("\"age\": 30"))
        #expect(result.json.contains("\"active\": true"))
    }

    @Test("Parses bare text as string")
    func bareTextString() {
        let input = "greeting: hello world"
        let result = JSONHelperParser.parse(input)
        #expect(result.error == nil)
        #expect(result.json.contains("\"greeting\": \"hello world\""))
    }

    @Test("Parses quoted text as string")
    func quotedString() {
        let input = "name: \"John\""
        let result = JSONHelperParser.parse(input)
        #expect(result.error == nil)
        #expect(result.json.contains("\"name\": \"John\""))
    }

    @Test("Quoted number becomes string")
    func quotedNumberAsString() {
        let input = "code: \"42\""
        let result = JSONHelperParser.parse(input)
        #expect(result.error == nil)
        #expect(result.json.contains("\"code\": \"42\""))
    }

    @Test("Bare number becomes number")
    func bareNumber() {
        let input = "count: 42"
        let result = JSONHelperParser.parse(input)
        #expect(result.error == nil)
        #expect(result.json.contains("\"count\": 42"))
    }

    @Test("Parses nested objects")
    func nestedObject() {
        let input = """
            address:
                city: New York
                zip: "10001"
            """
        let result = JSONHelperParser.parse(input)
        #expect(result.error == nil)
        #expect(result.json.contains("\"address\""))
        #expect(result.json.contains("\"city\": \"New York\""))
        #expect(result.json.contains("\"zip\": \"10001\""))
    }

    @Test("Parses arrays with bare strings")
    func arrays() {
        let input = """
            tags:
                - swift
                - macos
            """
        let result = JSONHelperParser.parse(input)
        #expect(result.error == nil)
        #expect(result.json.contains("\"tags\""))
        #expect(result.json.contains("\"swift\""))
        #expect(result.json.contains("\"macos\""))
    }

    @Test("Parses null values")
    func nullValue() {
        let input = "middle_name: null"
        let result = JSONHelperParser.parse(input)
        #expect(result.error == nil)
        #expect(result.json.contains("null"))
    }

    @Test("Parses boolean values")
    func booleans() {
        let input = """
            enabled: true
            deleted: false
            """
        let result = JSONHelperParser.parse(input)
        #expect(result.error == nil)
        #expect(result.json.contains("true"))
        #expect(result.json.contains("false"))
    }

    @Test("Parses negative numbers")
    func negativeNumbers() {
        let input = "offset: -10"
        let result = JSONHelperParser.parse(input)
        #expect(result.error == nil)
        #expect(result.json.contains("-10"))
    }

    @Test("Parses decimal numbers")
    func decimalNumbers() {
        let input = "price: 9.99"
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
        let input = "name: \"unterminated"
        let result = JSONHelperParser.parse(input)
        #expect(result.error != nil)
        #expect(result.error!.contains("unterminated"))
    }

    @Test("Handles escaped quotes in strings")
    func escapedQuotes() {
        let input = "say: \"hello \\\"world\\\"\""
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

    @Test("Bare array items become strings")
    func bareArrayItems() {
        let input = """
            items:
                - hello
                - world
                - 42
                - "42"
            """
        let result = JSONHelperParser.parse(input)
        #expect(result.error == nil)
        #expect(result.json.contains("\"hello\""))
        #expect(result.json.contains("\"world\""))
        // 42 without quotes is a number, "42" with quotes is a string
        #expect(result.json.contains("42,"))  // number 42 followed by comma
        #expect(result.json.contains("\"42\""))  // string "42"
    }

    @Test("Value containing colon is parsed correctly")
    func valueWithColon() {
        let input = "url: https://example.com:8080/path"
        let result = JSONHelperParser.parse(input)
        #expect(result.error == nil)
        #expect(result.json.contains("\"url\": \"https://example.com:8080/path\""))
    }

    // MARK: - fromJSON (JSON → Helper)

    @Test("Converts simple JSON to helper format with bare strings")
    func fromJSONSimple() {
        let json = "{\"name\": \"John\", \"age\": 30}"
        let helper = JSONHelperParser.fromJSON(json)
        #expect(helper != nil)
        #expect(helper!.contains("name: John"))
        #expect(helper!.contains("age: 30"))
    }

    @Test("Converts nested JSON to helper format with bare strings")
    func fromJSONNested() {
        let json = "{\"address\": {\"city\": \"NYC\"}}"
        let helper = JSONHelperParser.fromJSON(json)
        #expect(helper != nil)
        #expect(helper!.contains("address:"))
        #expect(helper!.contains("city: NYC"))
    }

    @Test("Converts JSON arrays to helper format with bare strings")
    func fromJSONArray() {
        let json = "{\"tags\": [\"a\", \"b\"]}"
        let helper = JSONHelperParser.fromJSON(json)
        #expect(helper != nil)
        #expect(helper!.contains("- a"))
        #expect(helper!.contains("- b"))
    }

    @Test("Quotes strings that look like numbers in reverse")
    func fromJSONQuotesNumericStrings() {
        let json = "{\"code\": \"42\", \"port\": \"8080\"}"
        let helper = JSONHelperParser.fromJSON(json)
        #expect(helper != nil)
        #expect(helper!.contains("code: \"42\""))
        #expect(helper!.contains("port: \"8080\""))
    }

    @Test("Quotes strings that look like booleans in reverse")
    func fromJSONQuotesBooleanStrings() {
        let json = "{\"answer\": \"true\", \"reply\": \"false\"}"
        let helper = JSONHelperParser.fromJSON(json)
        #expect(helper != nil)
        #expect(helper!.contains("answer: \"true\""))
        #expect(helper!.contains("reply: \"false\""))
    }

    @Test("Quotes strings that look like null in reverse")
    func fromJSONQuotesNullString() {
        let json = "{\"value\": \"null\"}"
        let helper = JSONHelperParser.fromJSON(json)
        #expect(helper != nil)
        #expect(helper!.contains("value: \"null\""))
    }

    @Test("Quotes empty strings in reverse")
    func fromJSONQuotesEmptyString() {
        let json = "{\"empty\": \"\"}"
        let helper = JSONHelperParser.fromJSON(json)
        #expect(helper != nil)
        #expect(helper!.contains("empty: \"\""))
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
            name: Alice
            age: 25
            active: true
            """
        let jsonResult = JSONHelperParser.parse(input)
        #expect(jsonResult.error == nil)
        let backToHelper = JSONHelperParser.fromJSON(jsonResult.json)
        #expect(backToHelper != nil)
        #expect(backToHelper!.contains("name: Alice"))
        #expect(backToHelper!.contains("age: 25"))
        #expect(backToHelper!.contains("active: true"))
    }

    @Test("Round-trip: quoted number stays quoted")
    func roundTripQuotedNumber() {
        let input = "zipcode: \"10001\""
        let jsonResult = JSONHelperParser.parse(input)
        #expect(jsonResult.error == nil)
        #expect(jsonResult.json.contains("\"zipcode\": \"10001\""))
        let backToHelper = JSONHelperParser.fromJSON(jsonResult.json)
        #expect(backToHelper != nil)
        #expect(backToHelper!.contains("zipcode: \"10001\""))
    }
}
