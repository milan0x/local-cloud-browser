import Testing
import Foundation
@testable import LocalCloudBrowser

@Suite("Config Models")
struct ConfigModelTests {

    // MARK: - ConfigurationRecorder

    @Test("parses from dict with recording group")
    func recorderInit() {
        let recorder = ConfigurationRecorder(from: [
            "name": "default",
            "roleARN": "arn:aws:iam::000:role/config-role",
            "recordingGroup": [
                "allSupported": false,
                "resourceTypes": ["AWS::S3::Bucket", "AWS::EC2::Instance"],
            ],
        ])
        #expect(recorder.name == "default")
        #expect(recorder.roleARN == "arn:aws:iam::000:role/config-role")
        #expect(recorder.allSupported == false)
        #expect(recorder.resourceTypes.count == 2)
        #expect(recorder.resourceTypes.contains("AWS::S3::Bucket"))
    }

    @Test("defaults allSupported to true when no recording group")
    func recorderDefaults() {
        let recorder = ConfigurationRecorder(from: ["name": "default", "roleARN": "arn:role"])
        #expect(recorder.allSupported == true)
        #expect(recorder.resourceTypes.isEmpty)
    }

    // MARK: - ConfigurationRecorderStatus

    @Test("parses status from dict")
    func recorderStatusInit() {
        let status = ConfigurationRecorderStatus(from: [
            "name": "default",
            "recording": true,
            "lastStatus": "SUCCESS",
            "lastStartTime": 1700000000.0,
        ])
        #expect(status.name == "default")
        #expect(status.recording == true)
        #expect(status.lastStatus == "SUCCESS")
        #expect(status.lastStartTime != nil)
    }

    // MARK: - DeliveryChannel

    @Test("parses from dict with delivery properties")
    func channelInit() {
        let channel = DeliveryChannel(from: [
            "name": "default",
            "s3BucketName": "config-bucket",
            "s3KeyPrefix": "config/",
            "snsTopicARN": "arn:aws:sns:us-east-1:000:config-topic",
            "configSnapshotDeliveryProperties": [
                "deliveryFrequency": "Six_Hours",
            ],
        ])
        #expect(channel.name == "default")
        #expect(channel.s3BucketName == "config-bucket")
        #expect(channel.s3KeyPrefix == "config/")
        #expect(channel.snsTopicARN == "arn:aws:sns:us-east-1:000:config-topic")
        #expect(channel.deliveryFrequency == "Six_Hours")
    }

    @Test("defaults delivery frequency to empty")
    func channelDefaultFrequency() {
        let channel = DeliveryChannel(from: ["name": "default", "s3BucketName": "bucket"])
        #expect(channel.deliveryFrequency == "")
    }

    // MARK: - CLI

    @Test("describeRecorderCLI generates valid command")
    func describeRecorderCLI() {
        let recorder = ConfigurationRecorder(from: ["name": "default", "roleARN": "arn:role"])
        let cli = recorder.describeRecorderCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws configservice describe-configuration-recorders"))
        #expect(cli.contains("default"))
    }

    @Test("listRecordersCLI generates valid command")
    func listRecordersCLI() {
        let cli = ConfigurationRecorder.listRecordersCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws configservice describe-configuration-recorders"))
    }

    @Test("describeChannelCLI generates valid command")
    func describeChannelCLI() {
        let channel = DeliveryChannel(from: ["name": "default", "s3BucketName": "bucket"])
        let cli = channel.describeChannelCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws configservice describe-delivery-channels"))
        #expect(cli.contains("default"))
    }
}
