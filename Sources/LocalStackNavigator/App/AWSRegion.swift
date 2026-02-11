import Foundation

struct AWSRegion {
    let code: String
    let displayName: String

    static let allRegions: [AWSRegion] = [
        // US East
        AWSRegion(code: "us-east-1", displayName: "US East (N. Virginia)"),
        AWSRegion(code: "us-east-2", displayName: "US East (Ohio)"),
        // US West
        AWSRegion(code: "us-west-1", displayName: "US West (N. California)"),
        AWSRegion(code: "us-west-2", displayName: "US West (Oregon)"),
        // Canada
        AWSRegion(code: "ca-central-1", displayName: "Canada (Central)"),
        AWSRegion(code: "ca-west-1", displayName: "Canada West (Calgary)"),
        // South America
        AWSRegion(code: "sa-east-1", displayName: "South America (São Paulo)"),
        // Europe
        AWSRegion(code: "eu-west-1", displayName: "Europe (Ireland)"),
        AWSRegion(code: "eu-west-2", displayName: "Europe (London)"),
        AWSRegion(code: "eu-west-3", displayName: "Europe (Paris)"),
        AWSRegion(code: "eu-central-1", displayName: "Europe (Frankfurt)"),
        AWSRegion(code: "eu-central-2", displayName: "Europe (Zurich)"),
        AWSRegion(code: "eu-north-1", displayName: "Europe (Stockholm)"),
        AWSRegion(code: "eu-south-1", displayName: "Europe (Milan)"),
        AWSRegion(code: "eu-south-2", displayName: "Europe (Spain)"),
        // Asia Pacific
        AWSRegion(code: "ap-east-1", displayName: "Asia Pacific (Hong Kong)"),
        AWSRegion(code: "ap-south-1", displayName: "Asia Pacific (Mumbai)"),
        AWSRegion(code: "ap-south-2", displayName: "Asia Pacific (Hyderabad)"),
        AWSRegion(code: "ap-southeast-1", displayName: "Asia Pacific (Singapore)"),
        AWSRegion(code: "ap-southeast-2", displayName: "Asia Pacific (Sydney)"),
        AWSRegion(code: "ap-southeast-3", displayName: "Asia Pacific (Jakarta)"),
        AWSRegion(code: "ap-southeast-4", displayName: "Asia Pacific (Melbourne)"),
        AWSRegion(code: "ap-southeast-5", displayName: "Asia Pacific (Malaysia)"),
        AWSRegion(code: "ap-northeast-1", displayName: "Asia Pacific (Tokyo)"),
        AWSRegion(code: "ap-northeast-2", displayName: "Asia Pacific (Seoul)"),
        AWSRegion(code: "ap-northeast-3", displayName: "Asia Pacific (Osaka)"),
        // Middle East
        AWSRegion(code: "me-south-1", displayName: "Middle East (Bahrain)"),
        AWSRegion(code: "me-central-1", displayName: "Middle East (UAE)"),
        // Africa
        AWSRegion(code: "af-south-1", displayName: "Africa (Cape Town)"),
        // Israel
        AWSRegion(code: "il-central-1", displayName: "Israel (Tel Aviv)"),
        // Asia Pacific (continued)
        AWSRegion(code: "ap-southeast-7", displayName: "Asia Pacific (Thailand)"),
        // Mexico
        AWSRegion(code: "mx-central-1", displayName: "Mexico (Central)"),
        // GovCloud
        AWSRegion(code: "us-gov-west-1", displayName: "AWS GovCloud (US-West)"),
        AWSRegion(code: "us-gov-east-1", displayName: "AWS GovCloud (US-East)"),
        // China
        AWSRegion(code: "cn-north-1", displayName: "China (Beijing)"),
        AWSRegion(code: "cn-northwest-1", displayName: "China (Ningxia)"),
        // Europe Sovereign
        AWSRegion(code: "eu-isoe-west-1", displayName: "Europe Sovereign (Germany)"),
        // AWS ISO
        AWSRegion(code: "us-iso-east-1", displayName: "US ISO East"),
        AWSRegion(code: "us-isob-east-1", displayName: "US ISOB East (Ohio)"),
    ]

    private static let codeSet: Set<String> = Set(allRegions.map(\.code))

    static func isValid(_ code: String) -> Bool {
        codeSet.contains(code)
    }

    static func find(_ code: String) -> AWSRegion? {
        allRegions.first { $0.code == code }
    }
}
