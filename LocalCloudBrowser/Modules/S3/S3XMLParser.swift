import Foundation

enum S3XMLParserError: Error, LocalizedError {
    case parseFailed(String)

    var errorDescription: String? {
        switch self {
        case .parseFailed(let detail):
            "Failed to parse S3 XML response: \(detail)"
        }
    }
}

// MARK: - Bucket List Parser

final class S3BucketListParser: NSObject, XMLParserDelegate {
    private var buckets: [S3Bucket] = []
    private var currentElement = ""
    private var currentName = ""
    private var currentDate = ""
    private var inBucket = false

    func parse(data: Data) throws -> [S3Bucket] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw S3XMLParserError.parseFailed(parser.parserError?.localizedDescription ?? "unknown")
        }
        return buckets
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        currentElement = elementName
        if elementName == "Bucket" {
            inBucket = true
            currentName = ""
            currentDate = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inBucket else { return }
        switch currentElement {
        case "Name":
            currentName += string
        case "CreationDate":
            currentDate += string
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        if elementName == "Bucket" {
            let date = DateFormatters.parseISO8601(currentDate)
            buckets.append(S3Bucket(name: currentName.trimmingCharacters(in: .whitespacesAndNewlines),
                                    creationDate: date))
            inBucket = false
        }
        currentElement = ""
    }
}

// MARK: - Object List Parser

struct S3ObjectListResult {
    let objects: [S3Object]
    let commonPrefixes: [S3Prefix]
    let isTruncated: Bool
    let nextContinuationToken: String?
    let keyCount: Int
    let maxKeys: Int
}

final class S3ObjectListParser: NSObject, XMLParserDelegate {
    private var objects: [S3Object] = []
    private var prefixes: [S3Prefix] = []
    private var currentElement = ""
    private var currentText = ""
    private var inContents = false
    private var inCommonPrefixes = false
    private var isTruncated = false
    private var nextContinuationToken: String?
    private var keyCount: Int = 0
    private var maxKeys: Int = 1000

    private var objKey = ""
    private var objSize: Int64 = 0
    private var objLastModified: Date?
    private var objEtag = ""
    private var objStorageClass = ""

    func parse(data: Data) throws -> S3ObjectListResult {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw S3XMLParserError.parseFailed(parser.parserError?.localizedDescription ?? "unknown")
        }
        return S3ObjectListResult(
            objects: objects,
            commonPrefixes: prefixes,
            isTruncated: isTruncated,
            nextContinuationToken: nextContinuationToken,
            keyCount: keyCount,
            maxKeys: maxKeys
        )
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""
        if elementName == "Contents" {
            inContents = true
            objKey = ""
            objSize = 0
            objLastModified = nil
            objEtag = ""
            objStorageClass = ""
        } else if elementName == "CommonPrefixes" {
            inCommonPrefixes = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if inContents {
            switch elementName {
            case "Key": objKey = text
            case "Size": objSize = Int64(text) ?? 0
            case "LastModified": objLastModified = DateFormatters.parseISO8601(text)
            case "ETag": objEtag = text
            case "StorageClass": objStorageClass = text
            case "Contents":
                objects.append(S3Object(
                    key: objKey, size: objSize, lastModified: objLastModified,
                    etag: objEtag, storageClass: objStorageClass
                ))
                inContents = false
            default: break
            }
        } else if inCommonPrefixes {
            switch elementName {
            case "Prefix":
                prefixes.append(S3Prefix(prefix: text))
            case "CommonPrefixes":
                inCommonPrefixes = false
            default: break
            }
        } else {
            switch elementName {
            case "IsTruncated":
                isTruncated = text.lowercased() == "true"
            case "NextContinuationToken":
                nextContinuationToken = text
            case "KeyCount":
                keyCount = Int(text) ?? 0
            case "MaxKeys":
                maxKeys = Int(text) ?? 1000
            default: break
            }
        }

        currentElement = ""
    }
}
