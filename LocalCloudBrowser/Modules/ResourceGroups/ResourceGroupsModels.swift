import Foundation

struct ResourceGroupSummary: Identifiable, Hashable {
    let name: String
    let groupArn: String
    let description: String

    var id: String { name }

    init(name: String = "", groupArn: String = "", description: String = "") {
        self.name = name
        self.groupArn = groupArn
        self.description = description
    }

    init(from dict: [String: Any]) {
        let group = dict["Group"] as? [String: Any] ?? dict
        name = group["Name"] as? String
            ?? group["GroupName"] as? String
            ?? dict["GroupName"] as? String
            ?? ""
        groupArn = group["GroupArn"] as? String ?? dict["GroupArn"] as? String ?? ""
        description = group["Description"] as? String ?? dict["Description"] as? String ?? ""
    }

    func getGroupCLI(endpointUrl: String, region: String) -> String {
        [
            "aws resource-groups get-group \\",
            "  --group-name '\(name.shellEscaped())' \\",
            "  --endpoint-url '\(endpointUrl)' \\",
            "  --region '\(region)'",
        ].joined(separator: "\n")
    }

    static func listGroupsCLI(endpointUrl: String, region: String) -> String {
        [
            "aws resource-groups list-groups \\",
            "  --endpoint-url '\(endpointUrl)' \\",
            "  --region '\(region)'",
        ].joined(separator: "\n")
    }

    func deleteGroupCLI(endpointUrl: String, region: String) -> String {
        [
            "aws resource-groups delete-group \\",
            "  --group-name '\(name.shellEscaped())' \\",
            "  --endpoint-url '\(endpointUrl)' \\",
            "  --region '\(region)'",
        ].joined(separator: "\n")
    }
}

struct ResourceGroupDetail {
    let name: String
    let groupArn: String
    let description: String
    var query: ResourceGroupQuery?
    var resources: [GroupResource]

    init(from dict: [String: Any]) {
        let group = dict["Group"] as? [String: Any] ?? dict
        name = group["Name"] as? String ?? group["GroupName"] as? String ?? ""
        groupArn = group["GroupArn"] as? String ?? ""
        description = group["Description"] as? String ?? ""
        query = nil
        resources = []
    }
}

struct ResourceGroupQuery {
    let type: String
    let tagFilters: [TagFilter]
    let resourceTypeFilters: [String]

    init(type: String = "TAG_FILTERS_1_0", tagFilters: [TagFilter] = [], resourceTypeFilters: [String] = []) {
        self.type = type
        self.tagFilters = tagFilters
        self.resourceTypeFilters = resourceTypeFilters
    }

    init(from dict: [String: Any]) {
        type = dict["Type"] as? String ?? "TAG_FILTERS_1_0"

        // The Query field is a JSON string that needs to be parsed
        if let queryStr = dict["Query"] as? String,
           let queryData = queryStr.data(using: .utf8),
           let queryObj = try? JSONSerialization.jsonObject(with: queryData) as? [String: Any] {
            if let filters = queryObj["TagFilters"] as? [[String: Any]] {
                tagFilters = filters.map { TagFilter(from: $0) }
            } else {
                tagFilters = []
            }
            resourceTypeFilters = queryObj["ResourceTypeFilters"] as? [String] ?? []
        } else {
            tagFilters = []
            resourceTypeFilters = []
        }
    }
}

struct TagFilter: Identifiable {
    let key: String
    let values: [String]

    var id: String { key }

    init(key: String = "", values: [String] = []) {
        self.key = key
        self.values = values
    }

    init(from dict: [String: Any]) {
        key = dict["Key"] as? String ?? ""
        values = dict["Values"] as? [String] ?? []
    }
}

struct GroupResource: Identifiable, Hashable {
    let resourceArn: String
    let resourceType: String
    let status: String

    var id: String { resourceArn }

    init(resourceArn: String = "", resourceType: String = "", status: String = "") {
        self.resourceArn = resourceArn
        self.resourceType = resourceType
        self.status = status
    }

    init(from dict: [String: Any]) {
        if let identifier = dict["ResourceArn"] as? String {
            resourceArn = identifier
        } else if let identifier = dict["Identifier"] as? [String: Any] {
            resourceArn = identifier["ResourceArn"] as? String ?? ""
        } else {
            resourceArn = ""
        }
        if let type = dict["ResourceType"] as? String {
            resourceType = type
        } else if let identifier = dict["Identifier"] as? [String: Any] {
            resourceType = identifier["ResourceType"] as? String ?? ""
        } else {
            resourceType = ""
        }
        if let statusDict = dict["Status"] as? [String: Any] {
            status = statusDict["Name"] as? String ?? ""
        } else {
            status = ""
        }
    }

    /// Short label for the resource type (e.g., "S3 Bucket" from "AWS::S3::Bucket")
    var shortTypeLabel: String {
        let parts = resourceType.split(separator: ":")
        guard parts.count >= 3 else { return resourceType }
        let service = String(parts[parts.count - 2])
        let resource = String(parts[parts.count - 1])
        return "\(service) \(resource)"
    }

    /// Color for the resource type badge based on the AWS service
    var typeColor: (label: String, color: String) {
        let lowered = resourceType.lowercased()
        if lowered.contains("s3") { return ("S3", "green") }
        if lowered.contains("lambda") { return ("Lambda", "orange") }
        if lowered.contains("dynamodb") { return ("DynamoDB", "blue") }
        if lowered.contains("ec2") { return ("EC2", "purple") }
        if lowered.contains("sqs") { return ("SQS", "teal") }
        if lowered.contains("sns") { return ("SNS", "pink") }
        if lowered.contains("rds") { return ("RDS", "indigo") }
        if lowered.contains("iam") { return ("IAM", "brown") }
        return ("AWS", "gray")
    }
}
