import Foundation

/// Parsed error response from LocalStack/AWS XML error bodies.
struct ServiceError: Identifiable {
    let id = UUID()
    let code: String
    let message: String

    /// Returns a user-friendly message for common AWS error codes,
    /// falling back to the raw `message` for unrecognized codes.
    var friendlyMessage: String {
        switch code {
        case "BucketNotEmpty":
            return "The bucket is not empty. Delete all objects first or use Force Delete."
        case "BucketAlreadyOwnedByYou", "BucketAlreadyExists":
            return "A bucket with this name already exists."
        case "NoSuchBucket":
            return "This bucket no longer exists. It may have been deleted."
        case "NoSuchKey":
            return "This object no longer exists. It may have been deleted or moved."
        case "QueueDoesNotExist":
            return "This queue no longer exists. It may have been deleted."
        case "QueueAlreadyExists":
            return "A queue with this name already exists with different attributes."
        case "NotFound":
            return "The requested resource was not found."
        case "InvalidParameterValue":
            return "One or more parameter values are invalid. Check your input and try again."
        case "AccessDenied":
            return "Access denied. Check your LocalStack configuration."
        default:
            return message
        }
    }

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

// MARK: - Error Extraction Helper

extension Error {
    /// Extracts a `ServiceError` from any error, unwrapping `CloudClientError`
    /// if present, or falling back to a generic error with `localizedDescription`.
    var asServiceError: ServiceError {
        if let clientError = self as? CloudClientError,
           let parsed = clientError.serviceError {
            return parsed
        }
        return ServiceError(code: "Error", message: localizedDescription)
    }
}
