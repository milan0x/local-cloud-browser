import Foundation

/// Coarse, user-facing permission categories. Each maps to a set of IAM actions.
/// Used by the permission helper's advanced-mode customizer to build an inline
/// policy tailored to the actions a user actually wants to perform.
struct PermissionCategory: Identifiable, Hashable {
    let id: String            // stable key within a service, e.g., "upload"
    let displayName: String   // user-visible label
    let actions: [String]     // IAM actions granted
}

/// Per-service category tables keyed by the SigV4 service name used by
/// `CloudClient` (same keys as `ServicePermissionRecipe.serviceKey` and
/// `Route.serviceKey`). Returns an empty list for services we haven't mapped.
enum ServiceActionCategories {
    static func categories(for serviceKey: String) -> [PermissionCategory] {
        switch serviceKey {
        case "s3":              return s3
        case "iam":             return iam
        case "sqs":             return sqs
        case "sns":             return sns
        case "dynamodb":        return dynamodb
        case "secretsmanager":  return secretsManager
        case "ssm":             return ssm
        case "monitoring":      return cloudWatch
        case "logs":            return cloudWatchLogs
        case "events":          return eventBridge
        case "kms":             return kms
        case "kinesis":         return kinesis
        case "firehose":        return firehose
        case "states":          return stepFunctions
        case "acm":             return acm
        default:                return []
        }
    }

    /// Finds the category whose action list contains the given IAM action.
    /// Used to pre-check the checkbox matching the user's current denied action.
    static func matching(action: String, in categories: [PermissionCategory]) -> PermissionCategory? {
        categories.first { $0.actions.contains(action) }
    }

    // MARK: - Per-service mappings

    static let s3: [PermissionCategory] = [
        PermissionCategory(id: "list-buckets", displayName: "List buckets",
                           actions: ["s3:ListAllMyBuckets", "s3:GetBucketLocation"]),
        PermissionCategory(id: "browse-objects", displayName: "Browse objects",
                           actions: ["s3:ListBucket", "s3:ListBucketVersions"]),
        PermissionCategory(id: "download", displayName: "Download",
                           actions: ["s3:GetObject", "s3:GetObjectVersion", "s3:GetObjectTagging"]),
        PermissionCategory(id: "upload", displayName: "Upload",
                           actions: ["s3:PutObject", "s3:PutObjectAcl", "s3:AbortMultipartUpload"]),
        PermissionCategory(id: "delete", displayName: "Delete",
                           actions: ["s3:DeleteObject", "s3:DeleteObjectVersion"]),
        PermissionCategory(id: "bucket-management", displayName: "Bucket management",
                           actions: ["s3:CreateBucket", "s3:DeleteBucket", "s3:PutBucketPolicy", "s3:GetBucketPolicy", "s3:DeleteBucketPolicy"]),
        PermissionCategory(id: "versioning-lifecycle", displayName: "Versioning & lifecycle",
                           actions: ["s3:GetBucketVersioning", "s3:PutBucketVersioning", "s3:GetLifecycleConfiguration", "s3:PutLifecycleConfiguration"]),
        PermissionCategory(id: "tags", displayName: "Tags & metadata",
                           actions: ["s3:GetBucketTagging", "s3:PutBucketTagging", "s3:GetObjectTagging", "s3:PutObjectTagging"]),
    ]

    static let iam: [PermissionCategory] = [
        PermissionCategory(id: "view-users", displayName: "View users",
                           actions: ["iam:ListUsers", "iam:GetUser", "iam:ListGroupsForUser", "iam:ListAttachedUserPolicies", "iam:ListUserPolicies", "iam:ListMFADevices"]),
        PermissionCategory(id: "view-roles", displayName: "View roles",
                           actions: ["iam:ListRoles", "iam:GetRole", "iam:ListAttachedRolePolicies", "iam:ListRolePolicies"]),
        PermissionCategory(id: "view-policies", displayName: "View policies",
                           actions: ["iam:ListPolicies", "iam:GetPolicy", "iam:GetPolicyVersion", "iam:ListPolicyVersions"]),
        PermissionCategory(id: "view-groups", displayName: "View groups",
                           actions: ["iam:ListGroups", "iam:GetGroup", "iam:ListAttachedGroupPolicies", "iam:ListGroupPolicies"]),
        PermissionCategory(id: "manage-users", displayName: "Manage users",
                           actions: ["iam:CreateUser", "iam:DeleteUser", "iam:UpdateUser", "iam:AttachUserPolicy", "iam:DetachUserPolicy", "iam:PutUserPolicy", "iam:DeleteUserPolicy"]),
        PermissionCategory(id: "manage-roles", displayName: "Manage roles",
                           actions: ["iam:CreateRole", "iam:DeleteRole", "iam:UpdateRole", "iam:AttachRolePolicy", "iam:DetachRolePolicy"]),
        PermissionCategory(id: "manage-policies", displayName: "Manage policies",
                           actions: ["iam:CreatePolicy", "iam:DeletePolicy", "iam:CreatePolicyVersion", "iam:DeletePolicyVersion", "iam:SetDefaultPolicyVersion"]),
    ]

    static let sqs: [PermissionCategory] = [
        PermissionCategory(id: "view", displayName: "View queues",
                           actions: ["sqs:ListQueues", "sqs:GetQueueUrl", "sqs:GetQueueAttributes", "sqs:ListQueueTags", "sqs:ListDeadLetterSourceQueues"]),
        PermissionCategory(id: "receive", displayName: "Receive messages",
                           actions: ["sqs:ReceiveMessage", "sqs:ChangeMessageVisibility", "sqs:ChangeMessageVisibilityBatch"]),
        PermissionCategory(id: "send", displayName: "Send messages",
                           actions: ["sqs:SendMessage", "sqs:SendMessageBatch"]),
        PermissionCategory(id: "delete-messages", displayName: "Delete messages",
                           actions: ["sqs:DeleteMessage", "sqs:DeleteMessageBatch", "sqs:PurgeQueue"]),
        PermissionCategory(id: "manage", displayName: "Manage queues",
                           actions: ["sqs:CreateQueue", "sqs:DeleteQueue", "sqs:SetQueueAttributes", "sqs:TagQueue", "sqs:UntagQueue"]),
    ]

    static let sns: [PermissionCategory] = [
        PermissionCategory(id: "view", displayName: "View topics",
                           actions: ["sns:ListTopics", "sns:GetTopicAttributes", "sns:ListSubscriptions", "sns:ListSubscriptionsByTopic", "sns:GetSubscriptionAttributes"]),
        PermissionCategory(id: "publish", displayName: "Publish",
                           actions: ["sns:Publish", "sns:PublishBatch"]),
        PermissionCategory(id: "subscribe", displayName: "Subscribe",
                           actions: ["sns:Subscribe", "sns:Unsubscribe", "sns:ConfirmSubscription"]),
        PermissionCategory(id: "manage", displayName: "Manage topics",
                           actions: ["sns:CreateTopic", "sns:DeleteTopic", "sns:SetTopicAttributes", "sns:TagResource", "sns:UntagResource"]),
    ]

    static let dynamodb: [PermissionCategory] = [
        PermissionCategory(id: "view", displayName: "View tables",
                           actions: ["dynamodb:ListTables", "dynamodb:DescribeTable", "dynamodb:DescribeTimeToLive", "dynamodb:ListTagsOfResource"]),
        PermissionCategory(id: "read", displayName: "Read items",
                           actions: ["dynamodb:GetItem", "dynamodb:BatchGetItem", "dynamodb:Query", "dynamodb:Scan"]),
        PermissionCategory(id: "write", displayName: "Write items",
                           actions: ["dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:BatchWriteItem"]),
        PermissionCategory(id: "delete", displayName: "Delete items",
                           actions: ["dynamodb:DeleteItem"]),
        PermissionCategory(id: "manage", displayName: "Manage tables",
                           actions: ["dynamodb:CreateTable", "dynamodb:DeleteTable", "dynamodb:UpdateTable", "dynamodb:TagResource", "dynamodb:UntagResource"]),
    ]

    static let secretsManager: [PermissionCategory] = [
        PermissionCategory(id: "view", displayName: "View secrets",
                           actions: ["secretsmanager:ListSecrets", "secretsmanager:DescribeSecret", "secretsmanager:ListSecretVersionIds"]),
        PermissionCategory(id: "read-values", displayName: "Read values",
                           actions: ["secretsmanager:GetSecretValue"]),
        PermissionCategory(id: "write-values", displayName: "Write values",
                           actions: ["secretsmanager:PutSecretValue", "secretsmanager:UpdateSecret", "secretsmanager:UpdateSecretVersionStage"]),
        PermissionCategory(id: "manage", displayName: "Manage secrets",
                           actions: ["secretsmanager:CreateSecret", "secretsmanager:DeleteSecret", "secretsmanager:RestoreSecret", "secretsmanager:TagResource", "secretsmanager:UntagResource", "secretsmanager:RotateSecret"]),
    ]

    static let ssm: [PermissionCategory] = [
        PermissionCategory(id: "view", displayName: "View parameters",
                           actions: ["ssm:DescribeParameters", "ssm:ListTagsForResource"]),
        PermissionCategory(id: "read", displayName: "Read values",
                           actions: ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath", "ssm:GetParameterHistory"]),
        PermissionCategory(id: "manage", displayName: "Manage parameters",
                           actions: ["ssm:PutParameter", "ssm:DeleteParameter", "ssm:DeleteParameters", "ssm:LabelParameterVersion"]),
    ]

    static let cloudWatch: [PermissionCategory] = [
        PermissionCategory(id: "view-metrics", displayName: "View metrics",
                           actions: ["cloudwatch:ListMetrics", "cloudwatch:GetMetricStatistics", "cloudwatch:GetMetricData"]),
        PermissionCategory(id: "view-alarms", displayName: "View alarms",
                           actions: ["cloudwatch:DescribeAlarms", "cloudwatch:DescribeAlarmsForMetric", "cloudwatch:DescribeAlarmHistory"]),
        PermissionCategory(id: "manage-alarms", displayName: "Manage alarms",
                           actions: ["cloudwatch:PutMetricAlarm", "cloudwatch:DeleteAlarms", "cloudwatch:SetAlarmState", "cloudwatch:EnableAlarmActions", "cloudwatch:DisableAlarmActions"]),
    ]

    static let cloudWatchLogs: [PermissionCategory] = [
        PermissionCategory(id: "view", displayName: "View log groups",
                           actions: ["logs:DescribeLogGroups", "logs:DescribeLogStreams"]),
        PermissionCategory(id: "read", displayName: "Read log events",
                           actions: ["logs:GetLogEvents", "logs:FilterLogEvents", "logs:StartQuery", "logs:GetQueryResults"]),
        PermissionCategory(id: "write", displayName: "Write logs",
                           actions: ["logs:CreateLogStream", "logs:PutLogEvents"]),
        PermissionCategory(id: "manage", displayName: "Manage log groups",
                           actions: ["logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:DeleteLogStream", "logs:PutRetentionPolicy"]),
    ]

    static let eventBridge: [PermissionCategory] = [
        PermissionCategory(id: "view", displayName: "View buses & rules",
                           actions: ["events:ListEventBuses", "events:ListRules", "events:DescribeRule", "events:ListTargetsByRule", "events:ListTagsForResource"]),
        PermissionCategory(id: "publish", displayName: "Publish events",
                           actions: ["events:PutEvents"]),
        PermissionCategory(id: "manage", displayName: "Manage rules",
                           actions: ["events:CreateEventBus", "events:DeleteEventBus", "events:PutRule", "events:DeleteRule", "events:PutTargets", "events:RemoveTargets", "events:EnableRule", "events:DisableRule"]),
    ]

    static let kms: [PermissionCategory] = [
        PermissionCategory(id: "view", displayName: "View keys",
                           actions: ["kms:ListKeys", "kms:DescribeKey", "kms:ListAliases", "kms:GetKeyPolicy", "kms:ListResourceTags"]),
        PermissionCategory(id: "use", displayName: "Use keys",
                           actions: ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey", "kms:ReEncryptFrom", "kms:ReEncryptTo"]),
        PermissionCategory(id: "manage", displayName: "Manage keys",
                           actions: ["kms:CreateKey", "kms:ScheduleKeyDeletion", "kms:EnableKey", "kms:DisableKey", "kms:PutKeyPolicy", "kms:CreateAlias", "kms:DeleteAlias"]),
    ]

    static let kinesis: [PermissionCategory] = [
        PermissionCategory(id: "view", displayName: "View streams",
                           actions: ["kinesis:ListStreams", "kinesis:DescribeStream", "kinesis:DescribeStreamSummary", "kinesis:ListShards", "kinesis:ListTagsForStream"]),
        PermissionCategory(id: "read", displayName: "Read records",
                           actions: ["kinesis:GetShardIterator", "kinesis:GetRecords"]),
        PermissionCategory(id: "write", displayName: "Write records",
                           actions: ["kinesis:PutRecord", "kinesis:PutRecords"]),
        PermissionCategory(id: "manage", displayName: "Manage streams",
                           actions: ["kinesis:CreateStream", "kinesis:DeleteStream", "kinesis:MergeShards", "kinesis:SplitShard"]),
    ]

    static let firehose: [PermissionCategory] = [
        PermissionCategory(id: "view", displayName: "View delivery streams",
                           actions: ["firehose:ListDeliveryStreams", "firehose:DescribeDeliveryStream"]),
        PermissionCategory(id: "put", displayName: "Put records",
                           actions: ["firehose:PutRecord", "firehose:PutRecordBatch"]),
        PermissionCategory(id: "manage", displayName: "Manage delivery streams",
                           actions: ["firehose:CreateDeliveryStream", "firehose:DeleteDeliveryStream", "firehose:UpdateDestination"]),
    ]

    static let stepFunctions: [PermissionCategory] = [
        PermissionCategory(id: "view", displayName: "View state machines",
                           actions: ["states:ListStateMachines", "states:DescribeStateMachine", "states:ListExecutions", "states:DescribeExecution", "states:GetExecutionHistory"]),
        PermissionCategory(id: "execute", displayName: "Execute",
                           actions: ["states:StartExecution", "states:StopExecution"]),
        PermissionCategory(id: "manage", displayName: "Manage state machines",
                           actions: ["states:CreateStateMachine", "states:DeleteStateMachine", "states:UpdateStateMachine"]),
    ]

    static let acm: [PermissionCategory] = [
        PermissionCategory(id: "view", displayName: "View certificates",
                           actions: ["acm:ListCertificates", "acm:DescribeCertificate", "acm:GetCertificate", "acm:ListTagsForCertificate"]),
        PermissionCategory(id: "request", displayName: "Request certificates",
                           actions: ["acm:RequestCertificate", "acm:ImportCertificate"]),
        PermissionCategory(id: "manage", displayName: "Manage certificates",
                           actions: ["acm:DeleteCertificate", "acm:AddTagsToCertificate", "acm:RemoveTagsFromCertificate", "acm:UpdateCertificateOptions"]),
    ]
}

/// Contextual framing helpers for denied actions. Drives the helper's header
/// copy so users immediately see what kind of permission they're missing.
enum DeniedActionKind {
    case browse, read, write, delete, create, manage, other

    var headerText: String {
        switch self {
        case .browse: "Browse permission needed"
        case .read:   "Read permission needed"
        case .write:  "Write permission needed"
        case .delete: "Delete permission needed"
        case .create: "Create permission needed"
        case .manage: "Management permission needed"
        case .other:  "Permission denied"
        }
    }

    /// Classifies an IAM action string (e.g. "s3:ListBucket") into a coarse kind.
    /// Matches on the action verb after the colon, not the service prefix.
    static func classify(_ action: String) -> DeniedActionKind {
        let verb = action.split(separator: ":").last.map(String.init) ?? action
        let lower = verb.lowercased()

        if lower.hasPrefix("delete") { return .delete }
        if lower.hasPrefix("create") { return .create }
        if lower.hasPrefix("update") || lower.hasPrefix("set") || lower.hasPrefix("put")
            || lower.hasPrefix("post") || lower.hasPrefix("send") || lower.hasPrefix("publish")
            || lower.hasPrefix("upload") || lower.hasPrefix("write") {
            return .write
        }
        if lower.hasPrefix("list") || lower.hasPrefix("describe")
            || lower.hasPrefix("head") || lower.contains("attributes") {
            return .browse
        }
        if lower.hasPrefix("get") { return .read }
        if lower.hasPrefix("attach") || lower.hasPrefix("detach")
            || lower.hasPrefix("enable") || lower.hasPrefix("disable")
            || lower.hasPrefix("tag") || lower.hasPrefix("untag") {
            return .manage
        }
        return .other
    }
}

/// Builds an inline IAM policy document from a set of selected categories.
enum CustomPolicyBuilder {
    static func policyJSON(for selected: Set<String>, in categories: [PermissionCategory]) -> String {
        let actions = categories
            .filter { selected.contains($0.id) }
            .flatMap(\.actions)
            .sorted()
        guard !actions.isEmpty else {
            return """
            {"Version":"2012-10-17","Statement":[]}
            """
        }
        let actionList = actions.map { "\"\($0)\"" }.joined(separator: ",")
        return """
        {"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":[\(actionList)],"Resource":"*"}]}
        """
    }

    static func putUserPolicyCommand(
        username: String,
        policyName: String,
        selected: Set<String>,
        categories: [PermissionCategory]
    ) -> String {
        let document = policyJSON(for: selected, in: categories)
        return """
        aws iam put-user-policy \\
          --user-name \(username) \\
          --policy-name \(policyName) \\
          --policy-document '\(document)'
        """
    }
}

/// UserDefaults-backed persistence for the advanced-mode toggle.
enum AdvancedPermissionMode {
    static let userDefaultsKey = "permissionHelperAdvancedMode"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: userDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: userDefaultsKey) }
    }
}
