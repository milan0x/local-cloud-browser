import Foundation

enum SNSXMLParseError: Error, LocalizedError {
    case parseFailure(String)

    var errorDescription: String? {
        switch self {
        case .parseFailure(let desc):
            return "XML parse error: \(desc)"
        }
    }
}

/// Parses SNS Query protocol XML responses.
///
/// Handles three common AWS XML patterns:
/// 1. Leaf text values — `first("TopicArn")`, `all("TopicArn")`
/// 2. Attribute entries — `<entry><key>K</key><value>V</value></entry>` via `attributeEntries()`
/// 3. Member groups — `<member><Field1>V1</Field1><Field2>V2</Field2></member>` via `memberGroups()`
final class SNSXMLParser: NSObject, XMLParserDelegate {
    private var elementStack: [String] = []
    private var currentText = ""

    // All leaf text values
    private(set) var leafValues: [(element: String, text: String)] = []

    // Member groups: each <member>...</member> becomes a [String: String] dict
    private(set) var memberDicts: [[String: String]] = []
    private var currentMember: [String: String]?

    // Attribute entries: <entry><key>K</key><value>V</value></entry>
    private var pendingKey: String?
    private(set) var attributeDict: [String: String] = [:]

    static func parse(_ data: Data) throws -> SNSXMLParser {
        let p = SNSXMLParser()
        let parser = XMLParser(data: data)
        parser.delegate = p
        if !parser.parse() {
            let desc = parser.parserError?.localizedDescription ?? "Unknown XML parse error"
            throw SNSXMLParseError.parseFailure(desc)
        }
        return p
    }

    /// First text value for an element name at any depth.
    func first(_ element: String) -> String? {
        leafValues.first { $0.element == element }?.text
    }

    /// All text values for an element name at any depth.
    func all(_ element: String) -> [String] {
        leafValues.filter { $0.element == element }.map(\.text)
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        elementStack.append(elementName)
        currentText = ""
        if elementName == "member" {
            currentMember = [:]
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmed.isEmpty {
            leafValues.append((element: elementName, text: trimmed))

            // Track fields inside <member>
            if currentMember != nil {
                currentMember?[elementName] = trimmed
            }

            // Track <entry><key>K</key><value>V</value></entry>
            let parent = elementStack.count >= 2 ? elementStack[elementStack.count - 2] : ""
            if elementName == "key" && parent == "entry" {
                pendingKey = trimmed
            } else if elementName == "value" && parent == "entry", let key = pendingKey {
                attributeDict[key] = trimmed
                pendingKey = nil
            }
        }

        // Finalize member group
        if elementName == "member", let member = currentMember, !member.isEmpty {
            memberDicts.append(member)
            currentMember = nil
        }

        elementStack.removeLast()
        currentText = ""
    }
}
