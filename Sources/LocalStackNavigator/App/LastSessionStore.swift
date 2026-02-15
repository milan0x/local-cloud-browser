import Foundation

struct LastSessionState: Codable {
    var routeRawValue: String?
    var s3BucketName: String?
    var s3Path: [String]?
    var sqsQueueName: String?
    var snsTopicArn: String?
    var secretName: String?
    var dynamodbTableName: String?
    var ssmParameterName: String?
    var lambdaFunctionName: String?
    var cloudWatchLogsLogGroupName: String?
    var eventBridgeBusName: String?
    var cloudFormationStackName: String?
    var iamEntityType: String?
    var iamEntityName: String?
    var apiGatewayAPIId: String?
    var kmsKeyId: String?
    var sesIdentityName: String?
    var acmCertificateArn: String?
    var kinesisStreamName: String?
    var kinesisTab: String?
    var kinesisFirehoseDeliveryStreamName: String?
    var route53HostedZoneId: String?
    var route53Tab: String?
    var route53ResolverEndpointId: String?
    var cloudWatchTab: String?
    var cloudWatchAlarmName: String?
    var redshiftClusterIdentifier: String?
    var opensearchDomainName: String?

    var route: Route? {
        guard let raw = routeRawValue else { return nil }
        return Route(rawValue: raw)
    }
}

enum LastSessionStore {
    private static let key = "lastSessionState"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: AppPreferences.restoreLastSessionKey)
    }

    static func load() -> LastSessionState? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(LastSessionState.self, from: data)
    }

    static func save(_ state: LastSessionState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func saveRoute(_ route: Route?) {
        var state = load() ?? LastSessionState()
        state.routeRawValue = route?.rawValue
        save(state)
    }

    static func saveS3Bucket(_ name: String?) {
        var state = load() ?? LastSessionState()
        state.s3BucketName = name
        save(state)
    }

    static func saveS3Path(_ components: [String]) {
        var state = load() ?? LastSessionState()
        state.s3Path = components
        save(state)
    }

    static func saveSQSQueue(_ name: String?) {
        var state = load() ?? LastSessionState()
        state.sqsQueueName = name
        save(state)
    }

    static func saveSNSTopic(_ arn: String?) {
        var state = load() ?? LastSessionState()
        state.snsTopicArn = arn
        save(state)
    }

    static func saveSecretsManagerSecret(_ name: String?) {
        var state = load() ?? LastSessionState()
        state.secretName = name
        save(state)
    }

    static func saveDynamoDBTable(_ name: String?) {
        var state = load() ?? LastSessionState()
        state.dynamodbTableName = name
        save(state)
    }

    static func saveSSMParameter(_ name: String?) {
        var state = load() ?? LastSessionState()
        state.ssmParameterName = name
        save(state)
    }

    static func saveLambdaFunction(_ name: String?) {
        var state = load() ?? LastSessionState()
        state.lambdaFunctionName = name
        save(state)
    }

    static func saveCloudWatchLogsLogGroup(_ name: String?) {
        var state = load() ?? LastSessionState()
        state.cloudWatchLogsLogGroupName = name
        save(state)
    }

    static func saveEventBridgeBus(_ name: String?) {
        var state = load() ?? LastSessionState()
        state.eventBridgeBusName = name
        save(state)
    }

    static func saveCloudFormationStack(_ name: String?) {
        var state = load() ?? LastSessionState()
        state.cloudFormationStackName = name
        save(state)
    }

    static func saveIAMEntity(type: String?, name: String?) {
        var state = load() ?? LastSessionState()
        state.iamEntityType = type
        state.iamEntityName = name
        save(state)
    }

    static func saveAPIGatewayAPI(_ id: String?) {
        var state = load() ?? LastSessionState()
        state.apiGatewayAPIId = id
        save(state)
    }

    static func saveKMSKey(_ id: String?) {
        var state = load() ?? LastSessionState()
        state.kmsKeyId = id
        save(state)
    }

    static func saveSESIdentity(_ name: String?) {
        var state = load() ?? LastSessionState()
        state.sesIdentityName = name
        save(state)
    }

    static func saveACMCertificate(_ arn: String?) {
        var state = load() ?? LastSessionState()
        state.acmCertificateArn = arn
        save(state)
    }

    static func saveKinesis(tab: String?, streamName: String?, deliveryStreamName: String?) {
        var state = load() ?? LastSessionState()
        state.kinesisTab = tab
        state.kinesisStreamName = streamName
        state.kinesisFirehoseDeliveryStreamName = deliveryStreamName
        save(state)
    }

    static func saveRoute53(tab: String?, hostedZoneId: String?, resolverEndpointId: String?) {
        var state = load() ?? LastSessionState()
        state.route53Tab = tab
        state.route53HostedZoneId = hostedZoneId
        state.route53ResolverEndpointId = resolverEndpointId
        save(state)
    }

    static func saveCloudWatch(tab: String?, alarmName: String?) {
        var state = load() ?? LastSessionState()
        state.cloudWatchTab = tab
        state.cloudWatchAlarmName = alarmName
        save(state)
    }

    static func saveRedshiftCluster(_ id: String?) {
        var state = load() ?? LastSessionState()
        state.redshiftClusterIdentifier = id
        save(state)
    }

    static func saveOpenSearchDomain(_ name: String?) {
        var state = load() ?? LastSessionState()
        state.opensearchDomainName = name
        save(state)
    }

    /// Clears per-module sub-resource fields (bucket, path, queue, topic) while
    /// keeping the route. Called on launch when cross-launch restore is
    /// disabled so modules start fresh. In-session onChange handlers
    /// repopulate these fields as the user makes selections.
    static func clearSubResources() {
        var state = load() ?? LastSessionState()
        state.s3BucketName = nil
        state.s3Path = nil
        state.sqsQueueName = nil
        state.snsTopicArn = nil
        state.secretName = nil
        state.dynamodbTableName = nil
        state.ssmParameterName = nil
        state.lambdaFunctionName = nil
        state.cloudWatchLogsLogGroupName = nil
        state.eventBridgeBusName = nil
        state.cloudFormationStackName = nil
        state.iamEntityType = nil
        state.iamEntityName = nil
        state.apiGatewayAPIId = nil
        state.kmsKeyId = nil
        state.sesIdentityName = nil
        state.acmCertificateArn = nil
        state.kinesisStreamName = nil
        state.kinesisTab = nil
        state.kinesisFirehoseDeliveryStreamName = nil
        state.route53HostedZoneId = nil
        state.route53Tab = nil
        state.route53ResolverEndpointId = nil
        state.cloudWatchTab = nil
        state.cloudWatchAlarmName = nil
        state.redshiftClusterIdentifier = nil
        state.opensearchDomainName = nil
        save(state)
    }
}
