import Foundation

/// Parsed error response from LocalStack/AWS XML error bodies.
struct ServiceError: Identifiable {
    let id = UUID()
    let code: String
    let message: String

    /// Attempts to parse an AWS-style error response (XML or JSON).
    ///
    /// XML format:
    /// ```xml
    /// <Error><Code>BucketNotEmpty</Code><Message>The bucket you tried to delete is not empty</Message></Error>
    /// ```
    /// JSON format (SQS/JSON protocol):
    /// ```json
    /// {"__type": "com.amazonaws.sqs#QueueDoesNotExist", "message": "..."}
    /// ```
    static func parse(from data: Data) -> ServiceError? {
        // Try XML first (S3, legacy protocols)
        let xmlResult = ErrorXMLParser(data: data).parse()
        if xmlResult != nil { return xmlResult }

        // Try JSON (SQS JSON protocol)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let rawType = json["__type"] as? String
        let message = (json["message"] as? String) ?? (json["Message"] as? String)
        guard let rawType, let message else { return nil }
        let code = rawType.components(separatedBy: "#").last ?? rawType
        return ServiceError(code: code, message: message)
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
