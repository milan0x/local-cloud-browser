import Testing
import Foundation
@testable import LocalCloudBrowser

@Suite("Kinesis Models")
struct KinesisModelTests {

    // MARK: - KinesisStreamSummary.statusBadgeColor

    @Test("statusBadgeColor maps statuses correctly")
    func statusBadgeColor() {
        #expect(KinesisStreamSummary(streamStatus: "ACTIVE").statusBadgeColor == "green")
        #expect(KinesisStreamSummary(streamStatus: "CREATING").statusBadgeColor == "orange")
        #expect(KinesisStreamSummary(streamStatus: "DELETING").statusBadgeColor == "red")
        #expect(KinesisStreamSummary(streamStatus: "UPDATING").statusBadgeColor == "blue")
        #expect(KinesisStreamSummary(streamStatus: "UNKNOWN").statusBadgeColor == "gray")
    }

    // MARK: - KinesisStreamSummary.init(from:)

    @Test("parses stream mode from nested dict")
    func streamModeFromDict() {
        let stream = KinesisStreamSummary(from: [
            "StreamName": "test",
            "StreamARN": "arn:test",
            "StreamStatus": "ACTIVE",
            "StreamModeDetails": ["StreamMode": "ON_DEMAND"],
        ])
        #expect(stream.streamMode == "ON_DEMAND")
    }

    @Test("defaults stream mode to PROVISIONED")
    func streamModeDefault() {
        let stream = KinesisStreamSummary(from: ["StreamName": "test", "StreamARN": "arn:test"])
        #expect(stream.streamMode == "PROVISIONED")
    }

    // MARK: - KinesisShard

    @Test("truncatedId truncates long IDs")
    func shardTruncatedId() {
        let shard = KinesisShard(from: [
            "ShardId": "shardId-000000000000-abcdefghijklmnop",
        ])
        #expect(shard.truncatedId.hasPrefix("..."))
        #expect(shard.truncatedId.count <= 23)
    }

    @Test("truncatedId returns short IDs as-is")
    func shardTruncatedIdShort() {
        let shard = KinesisShard(from: ["ShardId": "shard-1"])
        #expect(shard.truncatedId == "shard-1")
    }

    @Test("isClosed when endingSequenceNumber exists")
    func shardIsClosed() {
        let closed = KinesisShard(from: [
            "ShardId": "s1",
            "SequenceNumberRange": [
                "StartingSequenceNumber": "1",
                "EndingSequenceNumber": "100",
            ],
        ])
        #expect(closed.isClosed == true)

        let open = KinesisShard(from: [
            "ShardId": "s2",
            "SequenceNumberRange": ["StartingSequenceNumber": "1"],
        ])
        #expect(open.isClosed == false)
    }

    // MARK: - KinesisRecord

    @Test("decodedData decodes base64")
    func recordDecodedData() {
        let encoded = Data("Hello World".utf8).base64EncodedString()
        let record = KinesisRecord(from: [
            "SequenceNumber": "1",
            "PartitionKey": "pk",
            "Data": encoded,
        ])
        #expect(record.decodedData == "Hello World")
    }

    @Test("decodedData returns raw data if not valid base64")
    func recordDecodedDataInvalid() {
        let record = KinesisRecord(from: [
            "SequenceNumber": "1",
            "PartitionKey": "pk",
            "Data": "not-base64!!!",
        ])
        #expect(record.decodedData == "not-base64!!!")
    }

    @Test("isJSON detects JSON payload")
    func recordIsJSON() {
        let encoded = Data("{\"key\": \"value\"}".utf8).base64EncodedString()
        let record = KinesisRecord(from: [
            "SequenceNumber": "1",
            "PartitionKey": "pk",
            "Data": encoded,
        ])
        #expect(record.isJSON == true)
    }

    @Test("isJSON false for non-JSON payload")
    func recordNotJSON() {
        let encoded = Data("plain text".utf8).base64EncodedString()
        let record = KinesisRecord(from: [
            "SequenceNumber": "1",
            "PartitionKey": "pk",
            "Data": encoded,
        ])
        #expect(record.isJSON == false)
    }

    @Test("prettyJSON formats JSON payload")
    func recordPrettyJSON() {
        let encoded = Data("{\"a\":1}".utf8).base64EncodedString()
        let record = KinesisRecord(from: [
            "SequenceNumber": "1",
            "PartitionKey": "pk",
            "Data": encoded,
        ])
        #expect(record.prettyJSON != nil)
        #expect(record.prettyJSON!.contains("\"a\" : 1"))
    }

    // MARK: - FirehoseDeliveryStreamSummary

    @Test("FirehoseDeliveryStreamSummary parses from dict")
    func firehoseInit() {
        let stream = FirehoseDeliveryStreamSummary(from: [
            "DeliveryStreamName": "my-firehose",
            "DeliveryStreamARN": "arn:test",
            "DeliveryStreamStatus": "ACTIVE",
            "DeliveryStreamType": "DirectPut",
        ])
        #expect(stream.deliveryStreamName == "my-firehose")
        #expect(stream.deliveryStreamStatus == "ACTIVE")
    }

    // MARK: - FirehoseDestination

    @Test("FirehoseDestination detects ExtendedS3 type")
    func destinationExtendedS3() {
        let dest = FirehoseDestination(from: [
            "DestinationId": "d1",
            "ExtendedS3DestinationDescription": [
                "BucketARN": "arn:aws:s3:::my-bucket",
                "Prefix": "logs/",
                "CompressionFormat": "GZIP",
                "BufferingHints": ["IntervalInSeconds": 300, "SizeInMBs": 5],
            ],
        ])
        #expect(dest.type == "ExtendedS3")
        #expect(dest.bucketARN == "arn:aws:s3:::my-bucket")
        #expect(dest.prefix == "logs/")
        #expect(dest.compressionFormat == "GZIP")
        #expect(dest.bufferingIntervalInSeconds == 300)
        #expect(dest.bufferingSizeInMBs == 5)
    }

    @Test("FirehoseDestination detects HttpEndpoint type")
    func destinationHttpEndpoint() {
        let dest = FirehoseDestination(from: [
            "DestinationId": "d1",
            "HttpEndpointDestinationDescription": ["EndpointConfiguration": [:]],
        ])
        #expect(dest.type == "HttpEndpoint")
    }

    @Test("FirehoseDestination defaults to Unknown")
    func destinationUnknown() {
        let dest = FirehoseDestination(from: ["DestinationId": "d1"])
        #expect(dest.type == "Unknown")
    }

    // MARK: - CLI

    @Test("describeStreamCLI generates valid command")
    func describeStreamCLI() {
        let stream = KinesisStreamSummary(streamName: "my-stream")
        let cli = stream.describeStreamCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws kinesis describe-stream-summary"))
        #expect(cli.contains("my-stream"))
    }

    @Test("firehose describeStreamCLI generates valid command")
    func firehoseDescribeStreamCLI() {
        let stream = FirehoseDeliveryStreamSummary(deliveryStreamName: "my-firehose")
        let cli = stream.describeStreamCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws firehose describe-delivery-stream"))
        #expect(cli.contains("my-firehose"))
    }
}
