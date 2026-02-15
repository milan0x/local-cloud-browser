import Testing
@testable import LocalStackNavigator

@Suite("AWSRegion")
struct AWSRegionTests {

    @Test("isValid accepts known regions")
    func validRegions() {
        #expect(AWSRegion.isValid("us-east-1"))
        #expect(AWSRegion.isValid("eu-west-1"))
        #expect(AWSRegion.isValid("ap-northeast-1"))
    }

    @Test("isValid rejects unknown regions")
    func invalidRegions() {
        #expect(!AWSRegion.isValid("us-east-99"))
        #expect(!AWSRegion.isValid(""))
        #expect(!AWSRegion.isValid("invalid"))
    }

    @Test("find returns matching region")
    func findRegion() {
        let region = AWSRegion.find("us-east-1")
        #expect(region != nil)
        #expect(region?.code == "us-east-1")
        #expect(region?.displayName == "US East (N. Virginia)")
    }

    @Test("find returns nil for unknown code")
    func findUnknown() {
        #expect(AWSRegion.find("xx-north-1") == nil)
    }

    @Test("allRegions is not empty")
    func allRegionsPopulated() {
        #expect(AWSRegion.allRegions.count > 30)
    }

    @Test("GovCloud regions are valid")
    func govCloud() {
        #expect(AWSRegion.isValid("us-gov-west-1"))
        #expect(AWSRegion.isValid("us-gov-east-1"))
    }

    @Test("China regions are valid")
    func chinaRegions() {
        #expect(AWSRegion.isValid("cn-north-1"))
        #expect(AWSRegion.isValid("cn-northwest-1"))
    }
}
