import Foundation

struct JSONHelperParser {
    struct ParseResult {
        let json: String
        let error: String?
    }

    enum ParseError: Error, CustomStringConvertible {
        case inconsistentIndentation(line: Int)
        case unexpectedArrayItem(line: Int)
        case emptyKey(line: Int)
        case unterminatedString(line: Int)
        case duplicateKey(line: Int, key: String)

        var description: String {
            switch self {
            case .inconsistentIndentation(let line):
                return "Line \(line): inconsistent indentation"
            case .unexpectedArrayItem(let line):
                return "Line \(line): unexpected array item outside of array context"
            case .emptyKey(let line):
                return "Line \(line): empty key"
            case .unterminatedString(let line):
                return "Line \(line): unterminated string"
            case .duplicateKey(let line, let key):
                return "Line \(line): duplicate key '\(key)'"
            }
        }
    }

    static let defaultExample = """
        name: John Doe
        age: 30
        active: true
        address:
            city: New York
        tags:
            - swift
        """

    static let defaultJSON = parse(defaultExample).json

    static func parse(_ input: String) -> ParseResult {
        do {
            let lines = tokenize(input)
            guard !lines.isEmpty else {
                return ParseResult(json: "", error: nil)
            }
            let value = try buildValue(from: lines, start: 0, end: lines.count, baseIndent: lines[0].indent)
            let json = serialize(value, indent: 0)
            return ParseResult(json: json, error: nil)
        } catch let error as ParseError {
            return ParseResult(json: "", error: error.description)
        } catch {
            return ParseResult(json: "", error: error.localizedDescription)
        }
    }

    // MARK: - Tokenizer

    private struct Line {
        let lineNumber: Int    // 1-based for error messages
        let indent: Int        // number of leading spaces
        let isArrayItem: Bool  // starts with "- "
        let content: String    // after stripping indent and optional "- "
    }

    private static func tokenize(_ input: String) -> [Line] {
        var result: [Line] = []
        let rawLines = input.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, raw) in rawLines.enumerated() {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).count
            let afterIndent = String(line.dropFirst(indent))

            if afterIndent.hasPrefix("- ") {
                let content = String(afterIndent.dropFirst(2))
                result.append(Line(lineNumber: index + 1, indent: indent, isArrayItem: true, content: content))
            } else {
                result.append(Line(lineNumber: index + 1, indent: indent, isArrayItem: false, content: afterIndent))
            }
        }
        return result
    }

    // MARK: - Tree builder

    private enum JSONValue {
        case string(String)
        case number(String)
        case bool(Bool)
        case null
        case object([(String, JSONValue)])
        case array([JSONValue])
    }

    private static func buildValue(from lines: [Line], start: Int, end: Int, baseIndent: Int) throws -> JSONValue {
        // Check if all lines at this level are array items
        let topLevelLines = (start..<end).filter { lines[$0].indent == baseIndent }
        if !topLevelLines.isEmpty && topLevelLines.allSatisfy({ lines[$0].isArrayItem }) {
            return try buildArray(from: lines, start: start, end: end, baseIndent: baseIndent)
        }

        return try buildObject(from: lines, start: start, end: end, baseIndent: baseIndent)
    }

    private static func buildObject(from lines: [Line], start: Int, end: Int, baseIndent: Int) throws -> JSONValue {
        var pairs: [(String, JSONValue)] = []
        var seenKeys: Set<String> = []
        var i = start

        while i < end {
            let line = lines[i]

            if line.indent != baseIndent {
                throw ParseError.inconsistentIndentation(line: line.lineNumber)
            }
            if line.isArrayItem {
                throw ParseError.unexpectedArrayItem(line: line.lineNumber)
            }

            let (key, rawValue) = splitKeyValue(line.content)
            if key.isEmpty {
                throw ParseError.emptyKey(line: line.lineNumber)
            }
            if seenKeys.contains(key) {
                throw ParseError.duplicateKey(line: line.lineNumber, key: key)
            }
            seenKeys.insert(key)

            if let rawValue {
                // Key-value on same line
                let value = try parseValue(rawValue, lineNumber: line.lineNumber)
                pairs.append((key, value))
                i += 1
            } else {
                // Key only — children are indented below
                let childStart = i + 1
                let childEnd = findBlockEnd(lines: lines, from: childStart, end: end, parentIndent: baseIndent)

                if childStart < childEnd {
                    let childIndent = lines[childStart].indent
                    let childValue = try buildValue(from: lines, start: childStart, end: childEnd, baseIndent: childIndent)
                    pairs.append((key, childValue))
                } else {
                    // Key with no value and no children → empty string
                    pairs.append((key, .string("")))
                }
                i = childEnd
            }
        }

        return .object(pairs)
    }

    private static func buildArray(from lines: [Line], start: Int, end: Int, baseIndent: Int) throws -> JSONValue {
        var items: [JSONValue] = []
        var i = start

        while i < end {
            let line = lines[i]
            if line.indent != baseIndent { throw ParseError.inconsistentIndentation(line: line.lineNumber) }
            guard line.isArrayItem else { throw ParseError.unexpectedArrayItem(line: line.lineNumber) }

            let content = line.content.trimmingCharacters(in: .whitespaces)

            if content.isEmpty {
                // Array item with children on next lines
                let childStart = i + 1
                let childEnd = findBlockEnd(lines: lines, from: childStart, end: end, parentIndent: baseIndent)
                if childStart < childEnd {
                    let childIndent = lines[childStart].indent
                    let childValue = try buildValue(from: lines, start: childStart, end: childEnd, baseIndent: childIndent)
                    items.append(childValue)
                } else {
                    items.append(.string(""))
                }
                i = childEnd
            } else {
                // Inline value
                let value = try parseValue(content, lineNumber: line.lineNumber)
                items.append(value)
                i += 1
            }
        }

        return .array(items)
    }

    private static func findBlockEnd(lines: [Line], from start: Int, end: Int, parentIndent: Int) -> Int {
        var i = start
        while i < end {
            if lines[i].indent <= parentIndent { break }
            i += 1
        }
        return i
    }

    private static func splitKeyValue(_ content: String) -> (key: String, value: String?) {
        // If the content starts with a quote, it's not a key
        guard !content.hasPrefix("\"") else {
            return (content, nil)
        }

        // Split at first colon — "key: value" or "key:" (nested object)
        guard let colonIndex = content.firstIndex(of: ":") else {
            // No colon — key only (nested object or bare key)
            return (content.trimmingCharacters(in: .whitespaces), nil)
        }

        let key = String(content[content.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces)
        let value = String(content[content.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)

        if value.isEmpty {
            return (key, nil)
        }
        return (key, value)
    }

    // MARK: - Value parser

    private static func parseValue(_ raw: String, lineNumber: Int) throws -> JSONValue {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)

        // Boolean
        if trimmed == "true" { return .bool(true) }
        if trimmed == "false" { return .bool(false) }

        // Null
        if trimmed == "null" { return .null }

        // Quoted string
        if trimmed.hasPrefix("\"") {
            guard trimmed.count >= 2 && trimmed.hasSuffix("\"") else {
                throw ParseError.unterminatedString(line: lineNumber)
            }
            let inner = String(trimmed.dropFirst().dropLast())
            let unescaped = unescapeString(inner)
            return .string(unescaped)
        }

        // Number (integer or decimal)
        if let _ = Int(trimmed) {
            return .number(trimmed)
        }
        if let _ = Double(trimmed), trimmed.contains(".") {
            return .number(trimmed)
        }

        // Negative numbers
        if trimmed.hasPrefix("-") {
            let rest = String(trimmed.dropFirst())
            if let _ = Int(rest) { return .number(trimmed) }
            if let _ = Double(rest), rest.contains(".") { return .number(trimmed) }
        }

        // Bare text → string (no quotes needed for plain text)
        return .string(trimmed)
    }

    private static func unescapeString(_ input: String) -> String {
        var result = ""
        var chars = input.makeIterator()
        while let ch = chars.next() {
            if ch == "\\" {
                if let next = chars.next() {
                    switch next {
                    case "\"": result.append("\"")
                    case "\\": result.append("\\")
                    case "n": result.append("\n")
                    case "t": result.append("\t")
                    default:
                        result.append("\\")
                        result.append(next)
                    }
                } else {
                    result.append("\\")
                }
            } else {
                result.append(ch)
            }
        }
        return result
    }

    // MARK: - Serializer (preserves key order)

    private static func serialize(_ value: JSONValue, indent: Int) -> String {
        let indentStr = String(repeating: "    ", count: indent)
        let innerIndent = String(repeating: "    ", count: indent + 1)

        switch value {
        case .string(let s):
            return "\"\(escapeJSON(s))\""
        case .number(let n):
            return n
        case .bool(let b):
            return b ? "true" : "false"
        case .null:
            return "null"
        case .object(let pairs):
            if pairs.isEmpty { return "{}" }
            var parts: [String] = []
            for (key, val) in pairs {
                let serializedValue = serialize(val, indent: indent + 1)
                parts.append("\(innerIndent)\"\(escapeJSON(key))\": \(serializedValue)")
            }
            return "{\n\(parts.joined(separator: ",\n"))\n\(indentStr)}"
        case .array(let items):
            if items.isEmpty { return "[]" }
            var parts: [String] = []
            for item in items {
                let serializedValue = serialize(item, indent: indent + 1)
                parts.append("\(innerIndent)\(serializedValue)")
            }
            return "[\n\(parts.joined(separator: ",\n"))\n\(indentStr)]"
        }
    }

    private static func escapeJSON(_ s: String) -> String {
        var result = ""
        for ch in s {
            switch ch {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\t": result += "\\t"
            case "\r": result += "\\r"
            default: result.append(ch)
            }
        }
        return result
    }

    // MARK: - Reverse parser (JSON → Helper format)

    static func fromJSON(_ json: String) -> String? {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var scanner = JSONScanner(trimmed)
        guard let value = scanner.scanValue(), case .object = value else { return nil }
        return renderHelper(value, indent: 0)
    }

    private static func renderHelper(_ node: JSONValue, indent: Int) -> String {
        let pad = String(repeating: " ", count: indent)
        guard case .object(let pairs) = node else { return "" }

        return pairs.map { key, value in
            switch value {
            case .string(let s):
                return "\(pad)\(key): \(renderString(s))"
            case .number(let n):
                return "\(pad)\(key): \(n)"
            case .bool(let b):
                return "\(pad)\(key): \(b)"
            case .null:
                return "\(pad)\(key): null"
            case .object:
                return "\(pad)\(key):\n\(renderHelper(value, indent: indent + 4))"
            case .array(let items):
                let lines = items.map { item -> String in
                    switch item {
                    case .string(let s):
                        return "\(pad)    - \(renderString(s))"
                    case .number(let n):
                        return "\(pad)    - \(n)"
                    case .bool(let b):
                        return "\(pad)    - \(b)"
                    case .null:
                        return "\(pad)    - null"
                    case .object:
                        return "\(pad)    -\n\(renderHelper(item, indent: indent + 8))"
                    case .array:
                        return ""
                    }
                }
                return "\(pad)\(key):\n\(lines.joined(separator: "\n"))"
            }
        }.joined(separator: "\n")
    }

    private static func needsQuoting(_ s: String) -> Bool {
        if s.isEmpty { return true }
        if s == "true" || s == "false" || s == "null" { return true }
        if let _ = Int(s) { return true }
        if let _ = Double(s), s.contains(".") { return true }
        if s.hasPrefix("-") {
            let rest = String(s.dropFirst())
            if let _ = Int(rest) { return true }
            if let _ = Double(rest), rest.contains(".") { return true }
        }
        if s.contains("\\") || s.contains("\n") || s.contains("\t") || s.contains("\r") { return true }
        return false
    }

    private static func renderString(_ s: String) -> String {
        needsQuoting(s) ? "\"\(escapeJSON(s))\"" : s
    }

    // Minimal ordered JSON parser — preserves key order unlike JSONSerialization
    private struct JSONScanner {
        let chars: [Character]
        var i: Int

        init(_ string: String) {
            chars = Array(string)
            i = 0
        }

        mutating func scanValue() -> JSONValue? {
            skipWS()
            guard i < chars.count else { return nil }
            switch chars[i] {
            case "{": return scanObject()
            case "[": return scanArray()
            case "\"": return scanString().map { .string($0) }
            case "t", "f": return scanBool()
            case "n": return scanNull()
            default: return scanNumber()
            }
        }

        private mutating func skipWS() {
            while i < chars.count && chars[i].isWhitespace { i += 1 }
        }

        private mutating func scanObject() -> JSONValue? {
            guard i < chars.count && chars[i] == "{" else { return nil }
            i += 1
            skipWS()
            var pairs: [(String, JSONValue)] = []
            if i < chars.count && chars[i] == "}" { i += 1; return .object(pairs) }
            while true {
                skipWS()
                guard let key = scanString() else { return nil }
                skipWS()
                guard i < chars.count && chars[i] == ":" else { return nil }
                i += 1
                guard let value = scanValue() else { return nil }
                pairs.append((key, value))
                skipWS()
                guard i < chars.count else { return nil }
                if chars[i] == "}" { i += 1; return .object(pairs) }
                if chars[i] == "," { i += 1; continue }
                return nil
            }
        }

        private mutating func scanArray() -> JSONValue? {
            guard i < chars.count && chars[i] == "[" else { return nil }
            i += 1
            skipWS()
            var items: [JSONValue] = []
            if i < chars.count && chars[i] == "]" { i += 1; return .array(items) }
            while true {
                guard let value = scanValue() else { return nil }
                items.append(value)
                skipWS()
                guard i < chars.count else { return nil }
                if chars[i] == "]" { i += 1; return .array(items) }
                if chars[i] == "," { i += 1; continue }
                return nil
            }
        }

        private mutating func scanString() -> String? {
            skipWS()
            guard i < chars.count && chars[i] == "\"" else { return nil }
            i += 1
            var result = ""
            while i < chars.count && chars[i] != "\"" {
                if chars[i] == "\\" {
                    i += 1
                    guard i < chars.count else { return nil }
                    switch chars[i] {
                    case "\"": result.append("\"")
                    case "\\": result.append("\\")
                    case "/": result.append("/")
                    case "n": result.append("\n")
                    case "t": result.append("\t")
                    case "r": result.append("\r")
                    case "b": result.append("\u{08}")
                    case "f": result.append("\u{0C}")
                    case "u":
                        i += 1
                        guard i + 3 < chars.count else { return nil }
                        let hex = String(chars[i...i+3])
                        guard let code = UInt32(hex, radix: 16),
                              let scalar = Unicode.Scalar(code) else { return nil }
                        result.append(Character(scalar))
                        i += 3
                    default: result.append(chars[i])
                    }
                } else {
                    result.append(chars[i])
                }
                i += 1
            }
            guard i < chars.count && chars[i] == "\"" else { return nil }
            i += 1
            return result
        }

        private mutating func scanNumber() -> JSONValue? {
            let start = i
            if i < chars.count && chars[i] == "-" { i += 1 }
            while i < chars.count && chars[i].isNumber { i += 1 }
            if i < chars.count && chars[i] == "." {
                i += 1
                while i < chars.count && chars[i].isNumber { i += 1 }
            }
            if i < chars.count && (chars[i] == "e" || chars[i] == "E") {
                i += 1
                if i < chars.count && (chars[i] == "+" || chars[i] == "-") { i += 1 }
                while i < chars.count && chars[i].isNumber { i += 1 }
            }
            guard i > start else { return nil }
            return .number(String(chars[start..<i]))
        }

        private mutating func scanBool() -> JSONValue? {
            if i + 4 <= chars.count && String(chars[i..<i+4]) == "true" {
                i += 4; return .bool(true)
            }
            if i + 5 <= chars.count && String(chars[i..<i+5]) == "false" {
                i += 5; return .bool(false)
            }
            return nil
        }

        private mutating func scanNull() -> JSONValue? {
            if i + 4 <= chars.count && String(chars[i..<i+4]) == "null" {
                i += 4; return .null
            }
            return nil
        }
    }
}
