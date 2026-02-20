import Testing
import Foundation
@testable import LocalCloudBrowser

@Suite("EC2 Models")
struct EC2ModelTests {

    // MARK: - EC2InstanceState

    @Test("displayName maps correctly")
    func stateDisplayName() {
        #expect(EC2InstanceState.running.displayName == "Running")
        #expect(EC2InstanceState.stopped.displayName == "Stopped")
        #expect(EC2InstanceState.pending.displayName == "Pending")
        #expect(EC2InstanceState.terminated.displayName == "Terminated")
        #expect(EC2InstanceState.shuttingDown.displayName == "Shutting Down")
        #expect(EC2InstanceState.stopping.displayName == "Stopping")
    }

    @Test("canStart only when stopped")
    func canStart() {
        #expect(EC2InstanceState.stopped.canStart == true)
        #expect(EC2InstanceState.running.canStart == false)
        #expect(EC2InstanceState.pending.canStart == false)
        #expect(EC2InstanceState.terminated.canStart == false)
    }

    @Test("canStop only when running")
    func canStop() {
        #expect(EC2InstanceState.running.canStop == true)
        #expect(EC2InstanceState.stopped.canStop == false)
        #expect(EC2InstanceState.pending.canStop == false)
    }

    @Test("canTerminate for most states")
    func canTerminate() {
        #expect(EC2InstanceState.running.canTerminate == true)
        #expect(EC2InstanceState.stopped.canTerminate == true)
        #expect(EC2InstanceState.pending.canTerminate == true)
        #expect(EC2InstanceState.terminated.canTerminate == false)
        #expect(EC2InstanceState.shuttingDown.canTerminate == false)
    }

    @Test("canReboot only when running")
    func canReboot() {
        #expect(EC2InstanceState.running.canReboot == true)
        #expect(EC2InstanceState.stopped.canReboot == false)
        #expect(EC2InstanceState.terminated.canReboot == false)
    }

    @Test("Raw value for shutting-down")
    func shuttingDownRawValue() {
        #expect(EC2InstanceState(rawValue: "shutting-down") == .shuttingDown)
    }

    // MARK: - EC2Instance

    @Test("displayName returns nameTag when present")
    func displayNameWithTag() {
        let xml = """
            <instance>
                <instanceId>i-1234</instanceId>
                <imageId>ami-1234</imageId>
                <instanceType>t2.micro</instanceType>
                <instanceState><name>running</name><code>16</code></instanceState>
                <launchTime></launchTime>
                <tagSet>
                    <item><key>Name</key><value>WebServer</value></item>
                </tagSet>
            </instance>
            """
        let node = try! EC2XMLParser.parse(Data(xml.utf8))
        let instance = EC2Instance(from: node)
        #expect(instance.displayName == "WebServer")
    }

    @Test("displayName falls back to instanceId")
    func displayNameFallback() {
        let xml = """
            <instance>
                <instanceId>i-abcdef</instanceId>
                <imageId>ami-1234</imageId>
                <instanceType>t2.micro</instanceType>
                <instanceState><name>running</name><code>16</code></instanceState>
                <launchTime></launchTime>
            </instance>
            """
        let node = try! EC2XMLParser.parse(Data(xml.utf8))
        let instance = EC2Instance(from: node)
        #expect(instance.displayName == "i-abcdef")
    }

    @Test("parseDate handles ISO8601 with fractional seconds")
    func parseDateFractional() {
        let date = EC2Instance.parseDate("2024-01-15T10:30:00.000Z")
        #expect(date != nil)
    }

    @Test("parseDate handles ISO8601 without fractional seconds")
    func parseDateNoFraction() {
        let date = EC2Instance.parseDate("2024-01-15T10:30:00Z")
        #expect(date != nil)
    }

    @Test("parseDate returns nil for empty string")
    func parseDateEmpty() {
        #expect(EC2Instance.parseDate("") == nil)
    }

    @Test("parseDate returns nil for invalid string")
    func parseDateInvalid() {
        #expect(EC2Instance.parseDate("not a date") == nil)
    }

    // MARK: - EC2SecurityGroupRule

    @Test("protocolDisplay for all traffic")
    func protocolDisplayAll() {
        let rule = EC2SecurityGroupRule(ipProtocol: "-1", fromPort: nil, toPort: nil, cidrIp: "0.0.0.0/0", description: nil)
        #expect(rule.protocolDisplay == "All traffic")
    }

    @Test("protocolDisplay uppercases protocol")
    func protocolDisplayUpper() {
        let rule = EC2SecurityGroupRule(ipProtocol: "tcp", fromPort: 80, toPort: 80, cidrIp: "0.0.0.0/0", description: nil)
        #expect(rule.protocolDisplay == "TCP")
    }

    @Test("portRangeDisplay for all traffic")
    func portRangeAll() {
        let rule = EC2SecurityGroupRule(ipProtocol: "-1", fromPort: nil, toPort: nil, cidrIp: "0.0.0.0/0", description: nil)
        #expect(rule.portRangeDisplay == "All")
    }

    @Test("portRangeDisplay for ICMP")
    func portRangeICMP() {
        let rule = EC2SecurityGroupRule(ipProtocol: "icmp", fromPort: -1, toPort: -1, cidrIp: "0.0.0.0/0", description: nil)
        #expect(rule.portRangeDisplay == "N/A")
    }

    @Test("portRangeDisplay for single port")
    func portRangeSingle() {
        let rule = EC2SecurityGroupRule(ipProtocol: "tcp", fromPort: 443, toPort: 443, cidrIp: "0.0.0.0/0", description: nil)
        #expect(rule.portRangeDisplay == "443")
    }

    @Test("portRangeDisplay for port range")
    func portRangeRange() {
        let rule = EC2SecurityGroupRule(ipProtocol: "tcp", fromPort: 8000, toPort: 9000, cidrIp: "0.0.0.0/0", description: nil)
        #expect(rule.portRangeDisplay == "8000-9000")
    }

    @Test("portRangeDisplay for nil ports")
    func portRangeNil() {
        let rule = EC2SecurityGroupRule(ipProtocol: "tcp", fromPort: nil, toPort: nil, cidrIp: "0.0.0.0/0", description: nil)
        #expect(rule.portRangeDisplay == "All")
    }

    // MARK: - EC2XMLParser / EC2XMLNode

    @Test("Parses XML into tree structure")
    func parseXMLTree() throws {
        let xml = """
            <root>
                <child1>hello</child1>
                <child2>world</child2>
                <nested><deep>value</deep></nested>
            </root>
            """
        let root = try EC2XMLParser.parse(Data(xml.utf8))
        #expect(root.name == "root")
        #expect(root["child1"] == "hello")
        #expect(root["child2"] == "world")
        #expect(root.child("nested")?["deep"] == "value")
    }

    @Test("all() returns multiple matching children")
    func allChildren() throws {
        let xml = """
            <root>
                <item>a</item>
                <item>b</item>
                <item>c</item>
            </root>
            """
        let root = try EC2XMLParser.parse(Data(xml.utf8))
        let items = root.all("item")
        #expect(items.count == 3)
        #expect(items[0].text.trimmingCharacters(in: .whitespacesAndNewlines) == "a")
    }

    @Test("Subscript returns empty string for missing child")
    func subscriptMissing() throws {
        let xml = "<root><child>value</child></root>"
        let root = try EC2XMLParser.parse(Data(xml.utf8))
        #expect(root["nonexistent"] == "")
    }

    @Test("child() returns nil for missing child")
    func childMissing() throws {
        let xml = "<root><child>value</child></root>"
        let root = try EC2XMLParser.parse(Data(xml.utf8))
        #expect(root.child("nonexistent") == nil)
    }

    // MARK: - CLI

    @Test("describeInstanceCLI generates valid command")
    func describeInstanceCLI() {
        let xml = """
            <instance>
                <instanceId>i-1234</instanceId>
                <imageId>ami-1234</imageId>
                <instanceType>t2.micro</instanceType>
                <instanceState><name>running</name><code>16</code></instanceState>
                <launchTime></launchTime>
            </instance>
            """
        let node = try! EC2XMLParser.parse(Data(xml.utf8))
        let instance = EC2Instance(from: node)
        let cli = instance.describeInstanceCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws ec2 describe-instances"))
        #expect(cli.contains("i-1234"))
    }

    @Test("describeGroupCLI generates valid command")
    func describeGroupCLI() {
        let xml = """
            <securityGroup>
                <groupId>sg-1234</groupId>
                <groupName>default</groupName>
                <groupDescription>Default SG</groupDescription>
            </securityGroup>
            """
        let node = try! EC2XMLParser.parse(Data(xml.utf8))
        let sg = EC2SecurityGroup(from: node)
        let cli = sg.describeGroupCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws ec2 describe-security-groups"))
        #expect(cli.contains("sg-1234"))
    }

    @Test("describeKeyPairCLI generates valid command")
    func describeKeyPairCLI() {
        let xml = """
            <keyPair>
                <keyName>my-key</keyName>
                <keyPairId>kp-1234</keyPairId>
                <keyFingerprint>aa:bb:cc</keyFingerprint>
            </keyPair>
            """
        let node = try! EC2XMLParser.parse(Data(xml.utf8))
        let kp = EC2KeyPair(from: node)
        let cli = kp.describeKeyPairCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws ec2 describe-key-pairs"))
        #expect(cli.contains("my-key"))
    }
}
