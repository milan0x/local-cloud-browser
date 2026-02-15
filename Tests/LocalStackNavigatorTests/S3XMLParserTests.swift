import Testing
import Foundation
@testable import LocalStackNavigator

@Suite("S3 XML Parsers")
struct S3XMLParserTests {

    // MARK: - Bucket List Parser

    @Test("Parses bucket list XML")
    func parseBucketList() throws {
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <ListAllMyBucketsResult>
                <Buckets>
                    <Bucket>
                        <Name>my-bucket</Name>
                        <CreationDate>2024-01-15T10:30:00.000Z</CreationDate>
                    </Bucket>
                    <Bucket>
                        <Name>other-bucket</Name>
                        <CreationDate>2024-02-20T14:00:00.000Z</CreationDate>
                    </Bucket>
                </Buckets>
            </ListAllMyBucketsResult>
            """
        let buckets = try S3BucketListParser().parse(data: Data(xml.utf8))
        #expect(buckets.count == 2)
        #expect(buckets[0].name == "my-bucket")
        #expect(buckets[0].creationDate != nil)
        #expect(buckets[1].name == "other-bucket")
    }

    @Test("Parses empty bucket list")
    func parseEmptyBucketList() throws {
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <ListAllMyBucketsResult><Buckets></Buckets></ListAllMyBucketsResult>
            """
        let buckets = try S3BucketListParser().parse(data: Data(xml.utf8))
        #expect(buckets.isEmpty)
    }

    // MARK: - Object List Parser

    @Test("Parses object list XML")
    func parseObjectList() throws {
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <ListBucketResult>
                <IsTruncated>false</IsTruncated>
                <KeyCount>2</KeyCount>
                <MaxKeys>1000</MaxKeys>
                <Contents>
                    <Key>file.txt</Key>
                    <Size>1024</Size>
                    <LastModified>2024-01-15T10:30:00.000Z</LastModified>
                    <ETag>"abc123"</ETag>
                    <StorageClass>STANDARD</StorageClass>
                </Contents>
                <Contents>
                    <Key>folder/</Key>
                    <Size>0</Size>
                    <LastModified>2024-01-16T10:30:00.000Z</LastModified>
                    <ETag>""</ETag>
                    <StorageClass>STANDARD</StorageClass>
                </Contents>
                <CommonPrefixes>
                    <Prefix>images/</Prefix>
                </CommonPrefixes>
            </ListBucketResult>
            """
        let result = try S3ObjectListParser().parse(data: Data(xml.utf8))
        #expect(result.objects.count == 2)
        #expect(result.objects[0].key == "file.txt")
        #expect(result.objects[0].size == 1024)
        #expect(result.objects[0].storageClass == "STANDARD")
        #expect(result.objects[1].key == "folder/")
        #expect(result.commonPrefixes.count == 1)
        #expect(result.commonPrefixes[0].prefix == "images/")
        #expect(result.isTruncated == false)
        #expect(result.keyCount == 2)
        #expect(result.maxKeys == 1000)
    }

    @Test("Parses truncated result with continuation token")
    func parseTruncated() throws {
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <ListBucketResult>
                <IsTruncated>true</IsTruncated>
                <NextContinuationToken>abc123token</NextContinuationToken>
                <KeyCount>1</KeyCount>
                <MaxKeys>1</MaxKeys>
                <Contents>
                    <Key>only-one.txt</Key>
                    <Size>512</Size>
                    <LastModified>2024-01-15T10:30:00.000Z</LastModified>
                    <ETag>"def456"</ETag>
                    <StorageClass>STANDARD</StorageClass>
                </Contents>
            </ListBucketResult>
            """
        let result = try S3ObjectListParser().parse(data: Data(xml.utf8))
        #expect(result.isTruncated == true)
        #expect(result.nextContinuationToken == "abc123token")
        #expect(result.objects.count == 1)
    }

    @Test("Parses empty object list")
    func parseEmptyObjectList() throws {
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <ListBucketResult>
                <IsTruncated>false</IsTruncated>
                <KeyCount>0</KeyCount>
                <MaxKeys>1000</MaxKeys>
            </ListBucketResult>
            """
        let result = try S3ObjectListParser().parse(data: Data(xml.utf8))
        #expect(result.objects.isEmpty)
        #expect(result.commonPrefixes.isEmpty)
    }
}
