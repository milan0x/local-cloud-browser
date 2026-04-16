import Testing
import Foundation
@testable import LocalCloudBrowser

@Suite("Multipart Upload Plan")
struct MultipartUploadPlanTests {

    @Test("Small file produces single non-multipart plan")
    func smallFile() {
        let plan = MultipartUploadPlan.plan(fileSize: 1024)
        #expect(!plan.isMultipart)
        #expect(plan.parts.count == 1)
        #expect(plan.parts[0].offset == 0)
        #expect(plan.parts[0].length == 1024)
    }

    @Test("File at exactly minimumPartSize is not multipart")
    func exactMinimum() {
        let size = Int64(MultipartUploadPlan.minimumPartSize)
        let plan = MultipartUploadPlan.plan(fileSize: size)
        #expect(!plan.isMultipart)
    }

    @Test("File over minimumPartSize triggers multipart")
    func overMinimum() {
        let size = Int64(MultipartUploadPlan.minimumPartSize) + 1
        let plan = MultipartUploadPlan.plan(fileSize: size)
        #expect(plan.isMultipart)
        #expect(plan.parts.count >= 1)
    }

    @Test("Part offsets are contiguous")
    func contiguousOffsets() {
        let size: Int64 = 50 * 1024 * 1024 // 50 MB
        let plan = MultipartUploadPlan.plan(fileSize: size)
        var expectedOffset: Int64 = 0
        for part in plan.parts {
            #expect(part.offset == expectedOffset)
            expectedOffset += Int64(part.length)
        }
        #expect(expectedOffset == size)
    }

    @Test("Large file scales part size to stay under 10000 parts")
    func largeFileScaling() {
        let size: Int64 = 100 * 1024 * 1024 * 1024 // 100 GB
        let plan = MultipartUploadPlan.plan(fileSize: size)
        #expect(plan.isMultipart)
        #expect(plan.parts.count <= MultipartUploadPlan.maximumPartCount)
    }

    @Test("Zero-byte file produces non-multipart single-part plan")
    func zeroByteFile() {
        let plan = MultipartUploadPlan.plan(fileSize: 0)
        #expect(!plan.isMultipart)
        #expect(plan.parts.count == 1)
        #expect(plan.parts[0].length == 0)
    }

    @Test("completeMultipartXML sorts parts by number")
    func xmlSorting() {
        let parts = [
            CompletedPart(partNumber: 3, etag: "\"etag3\""),
            CompletedPart(partNumber: 1, etag: "\"etag1\""),
            CompletedPart(partNumber: 2, etag: "\"etag2\""),
        ]
        let xml = String(data: MultipartUploadPlan.completeMultipartXML(parts: parts), encoding: .utf8)!
        #expect(xml.contains("<CompleteMultipartUpload>"))
        // Verify ordering: part 1 should appear before part 2
        let range1 = xml.range(of: "<PartNumber>1</PartNumber>")!
        let range2 = xml.range(of: "<PartNumber>2</PartNumber>")!
        let range3 = xml.range(of: "<PartNumber>3</PartNumber>")!
        #expect(range1.lowerBound < range2.lowerBound)
        #expect(range2.lowerBound < range3.lowerBound)
    }
}
