import Foundation

struct OpenSearchDomain: Identifiable, Hashable {
    let domainName: String
    let domainId: String
    let arn: String
    let engineVersion: String
    let endpoint: String
    let processing: Bool
    let created: Bool
    let deleted: Bool
    let instanceType: String
    let instanceCount: Int
    let ebsEnabled: Bool
    let volumeType: String
    let volumeSize: Int

    var id: String { domainName }

    var status: String {
        if deleted { return "Deleting" }
        if processing { return "Processing" }
        if created { return "Active" }
        return "Unknown"
    }

    var statusColor: String {
        switch status {
        case "Active": return "green"
        case "Processing": return "blue"
        case "Deleting": return "red"
        default: return "gray"
        }
    }

    var engineDisplayName: String {
        engineVersion.replacingOccurrences(of: "_", with: " ")
    }

    init(domainName: String = "", domainId: String = "", arn: String = "",
         engineVersion: String = "", endpoint: String = "",
         processing: Bool = false, created: Bool = true, deleted: Bool = false,
         instanceType: String = "", instanceCount: Int = 1,
         ebsEnabled: Bool = true, volumeType: String = "", volumeSize: Int = 0) {
        self.domainName = domainName
        self.domainId = domainId
        self.arn = arn
        self.engineVersion = engineVersion
        self.endpoint = endpoint
        self.processing = processing
        self.created = created
        self.deleted = deleted
        self.instanceType = instanceType
        self.instanceCount = instanceCount
        self.ebsEnabled = ebsEnabled
        self.volumeType = volumeType
        self.volumeSize = volumeSize
    }

    init(json: [String: Any]) {
        self.domainName = json["DomainName"] as? String ?? ""
        self.domainId = json["DomainId"] as? String ?? ""
        self.arn = json["ARN"] as? String ?? ""
        self.engineVersion = json["EngineVersion"] as? String ?? ""
        self.endpoint = json["Endpoint"] as? String ?? json["Endpoints"] as? String ?? ""
        self.processing = json["Processing"] as? Bool ?? false
        self.created = json["Created"] as? Bool ?? true
        self.deleted = json["Deleted"] as? Bool ?? false

        let clusterConfig = json["ClusterConfig"] as? [String: Any] ?? [:]
        self.instanceType = clusterConfig["InstanceType"] as? String ?? ""
        self.instanceCount = clusterConfig["InstanceCount"] as? Int ?? 1

        let ebsOptions = json["EBSOptions"] as? [String: Any] ?? [:]
        self.ebsEnabled = ebsOptions["EBSEnabled"] as? Bool ?? true
        self.volumeType = ebsOptions["VolumeType"] as? String ?? ""
        self.volumeSize = ebsOptions["VolumeSize"] as? Int ?? 0
    }

    /// Shell-escape a string for use inside single quotes: replace `'` with `'\''`
    private static func shellEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "'\\''")
    }

    func describeDomainCLI(endpointUrl: String, region: String) -> String {
        [
            "aws opensearch describe-domain \\",
            "  --domain-name '\(Self.shellEscape(domainName))' \\",
            "  --endpoint-url \(endpointUrl) \\",
            "  --region \(region)"
        ].joined(separator: "\n")
    }

    func deleteDomainCLI(endpointUrl: String, region: String) -> String {
        [
            "aws opensearch delete-domain \\",
            "  --domain-name '\(Self.shellEscape(domainName))' \\",
            "  --endpoint-url \(endpointUrl) \\",
            "  --region \(region)"
        ].joined(separator: "\n")
    }

    static func listDomainsCLI(endpointUrl: String, region: String) -> String {
        [
            "aws opensearch list-domain-names \\",
            "  --endpoint-url \(endpointUrl) \\",
            "  --region \(region)"
        ].joined(separator: "\n")
    }
}
