import Foundation

/// Parsed error response from LocalStack/AWS XML error bodies.
struct ServiceError: Identifiable {
    let id = UUID()
    let code: String
    let message: String

    /// Attempts to parse an AWS-style XML error response.
    ///
    /// Expected format:
    /// ```xml
    /// <Error><Code>BucketNotEmpty</Code><Message>The bucket you tried to delete is not empty</Message></Error>
    /// ```
    static func parse(from data: Data) -> ServiceError? {
        let parser = ErrorXMLParser(data: data)
        return parser.parse()
    }
}

// MARK: - XML Parser

private final class ErrorXMLParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var code: String?
    private var message: String?
    private var currentElement: String?
    private var currentText = ""

    init(data: Data) {
        self.data = data
    }

    func parse() -> ServiceError? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse(), let code, let message else { return nil }
        return ServiceError(code: code, message: message)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "Code":
            code = trimmed
        case "Message":
            message = trimmed
        default:
            break
        }
        currentElement = nil
    }
}
