import Foundation

final class CloudFormationService: BaseService {
    // MARK: - Stacks

    func listStacksPage(region: String? = nil, token: String? = nil) async throws -> ([CloudFormationStack], String?) {
        // Exclude DELETE_COMPLETE stacks by default
        let statusFilters = [
            "CREATE_IN_PROGRESS", "CREATE_FAILED", "CREATE_COMPLETE",
            "ROLLBACK_IN_PROGRESS", "ROLLBACK_FAILED", "ROLLBACK_COMPLETE",
            "DELETE_IN_PROGRESS", "DELETE_FAILED",
            "UPDATE_IN_PROGRESS", "UPDATE_COMPLETE_CLEANUP_IN_PROGRESS",
            "UPDATE_COMPLETE", "UPDATE_FAILED",
            "UPDATE_ROLLBACK_IN_PROGRESS", "UPDATE_ROLLBACK_FAILED",
            "UPDATE_ROLLBACK_COMPLETE_CLEANUP_IN_PROGRESS", "UPDATE_ROLLBACK_COMPLETE",
            "REVIEW_IN_PROGRESS",
        ]

        var params: [String: String] = [:]
        for (i, status) in statusFilters.enumerated() {
            params["StackStatusFilter.member.\(i + 1)"] = status
        }
        if let token {
            params["NextToken"] = token
        }
        let data = try await client.cloudFormationRequest(action: "ListStacks", params: params, region: region)
        let xml = try SNSXMLParser.parse(data)

        let stacks = xml.memberDicts.map { CloudFormationStack(from: $0) }
        return (stacks, xml.first("NextToken"))
    }

    func listStacks(region: String? = nil) async throws -> [CloudFormationStack] {
        var allStacks: [CloudFormationStack] = []
        var nextToken: String? = nil

        repeat {
            let (stacks, token) = try await listStacksPage(region: region, token: nextToken)
            allStacks.append(contentsOf: stacks)
            nextToken = token
            if allStacks.count >= 10_000 { break }
        } while nextToken != nil

        return allStacks
    }

    func describeStack(name: String) async throws -> CloudFormationStackDetail {
        let data = try await client.cloudFormationRequest(
            action: "DescribeStacks",
            params: ["StackName": name]
        )
        // DescribeStacks returns nested members (parameters/outputs inside a stack member).
        // Use a custom parser that handles the nesting.
        let rawString = String(data: data, encoding: .utf8) ?? ""
        return try parseStackDetail(from: rawString)
    }

    func createStack(name: String, templateBody: String, parameters: [CFParameter]) async throws {
        var params: [String: String] = [
            "StackName": name,
            "TemplateBody": templateBody,
        ]
        for (i, param) in parameters.enumerated() {
            params["Parameters.member.\(i + 1).ParameterKey"] = param.parameterKey
            params["Parameters.member.\(i + 1).ParameterValue"] = param.parameterValue
        }
        _ = try await client.cloudFormationRequest(action: "CreateStack", params: params)
    }

    func updateStack(name: String, templateBody: String, parameters: [CFParameter]) async throws {
        var params: [String: String] = [
            "StackName": name,
            "TemplateBody": templateBody,
        ]
        for (i, param) in parameters.enumerated() {
            params["Parameters.member.\(i + 1).ParameterKey"] = param.parameterKey
            params["Parameters.member.\(i + 1).ParameterValue"] = param.parameterValue
        }
        _ = try await client.cloudFormationRequest(action: "UpdateStack", params: params)
    }

    func deleteStack(name: String) async throws {
        _ = try await client.cloudFormationRequest(
            action: "DeleteStack",
            params: ["StackName": name]
        )
    }

    // MARK: - Resources

    func listStackResourcesPage(name: String, token: String? = nil) async throws -> ([CloudFormationResource], String?) {
        var params: [String: String] = ["StackName": name]
        if let token {
            params["NextToken"] = token
        }
        let data = try await client.cloudFormationRequest(action: "ListStackResources", params: params)
        let xml = try SNSXMLParser.parse(data)

        let resources = xml.memberDicts.map { CloudFormationResource(from: $0) }
        return (resources, xml.first("NextToken"))
    }

    func listStackResources(name: String) async throws -> [CloudFormationResource] {
        var allResources: [CloudFormationResource] = []
        var nextToken: String? = nil

        repeat {
            let (resources, token) = try await listStackResourcesPage(name: name, token: nextToken)
            allResources.append(contentsOf: resources)
            nextToken = token
            if allResources.count >= 10_000 { break }
        } while nextToken != nil

        return allResources
    }

    // MARK: - Events

    func describeStackEventsPage(name: String, token: String? = nil) async throws -> ([CloudFormationEvent], String?) {
        var params: [String: String] = ["StackName": name]
        if let token {
            params["NextToken"] = token
        }
        let data = try await client.cloudFormationRequest(action: "DescribeStackEvents", params: params)
        let xml = try SNSXMLParser.parse(data)

        let events = xml.memberDicts.map { CloudFormationEvent(from: $0) }
        return (events, xml.first("NextToken"))
    }

    func describeStackEvents(name: String) async throws -> [CloudFormationEvent] {
        var allEvents: [CloudFormationEvent] = []
        var nextToken: String? = nil

        repeat {
            let (events, token) = try await describeStackEventsPage(name: name, token: nextToken)
            allEvents.append(contentsOf: events)
            nextToken = token
            if allEvents.count >= 10_000 { break }
        } while nextToken != nil

        return allEvents
    }

    // MARK: - Template

    func getTemplate(name: String) async throws -> String {
        let data = try await client.cloudFormationRequest(
            action: "GetTemplate",
            params: ["StackName": name]
        )
        let xml = try SNSXMLParser.parse(data)
        return xml.first("TemplateBody") ?? ""
    }

    // MARK: - Detail Parsing

    /// Parse DescribeStacks XML response to extract full stack detail including parameters and outputs.
    private func parseStackDetail(from xmlString: String) throws -> CloudFormationStackDetail {
        guard let data = xmlString.data(using: .utf8) else {
            throw CloudClientError.invalidURL
        }
        let parser = CloudFormationDetailParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        guard xmlParser.parse() else {
            throw SNSXMLParseError.parseFailure(xmlParser.parserError?.localizedDescription ?? "Unknown")
        }
        guard let detail = parser.buildDetail() else {
            throw CloudClientError.invalidURL
        }
        return detail
    }
}

// MARK: - DescribeStacks Detail Parser

/// Custom XML parser for DescribeStacks that handles nested member groups
/// (Parameters, Outputs are nested members inside the stack member).
private final class CloudFormationDetailParser: NSObject, XMLParserDelegate {
    private var elementStack: [String] = []
    private var currentText = ""

    // Stack-level fields
    private var stackFields: [String: String] = [:]

    // Nested collections
    private var parameters: [[String: String]] = []
    private var outputs: [[String: String]] = []
    private var capabilities: [String] = []

    // Track which collection context we're in
    private var inParameters = false
    private var inOutputs = false
    private var inCapabilities = false
    private var currentMember: [String: String]?
    private var memberDepth = 0

    func buildDetail() -> CloudFormationStackDetail? {
        guard !stackFields.isEmpty else { return nil }
        return CloudFormationStackDetail(
            stackName: stackFields["StackName"] ?? "",
            stackId: stackFields["StackId"] ?? "",
            stackStatus: stackFields["StackStatus"] ?? "",
            creationTime: CloudFormationStack.parseDate(stackFields["CreationTime"]),
            lastUpdatedTime: CloudFormationStack.parseDate(stackFields["LastUpdatedTime"]),
            templateDescription: stackFields["Description"],
            capabilities: capabilities,
            roleARN: stackFields["RoleARN"],
            parameters: parameters.map { CFParameter(from: $0) },
            outputs: outputs.map { CFOutput(from: $0) }
        )
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        elementStack.append(elementName)
        currentText = ""

        if elementName == "Parameters" { inParameters = true }
        else if elementName == "Outputs" { inOutputs = true }
        else if elementName == "Capabilities" { inCapabilities = true }

        if elementName == "member" {
            memberDepth += 1
            if memberDepth >= 2 {
                // Nested member (parameter or output)
                currentMember = [:]
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if elementName == "member" {
            if memberDepth >= 2, let member = currentMember, !member.isEmpty {
                if inParameters {
                    parameters.append(member)
                } else if inOutputs {
                    outputs.append(member)
                }
                currentMember = nil
            }
            memberDepth -= 1
        } else if elementName == "Parameters" {
            inParameters = false
        } else if elementName == "Outputs" {
            inOutputs = false
        } else if elementName == "Capabilities" {
            inCapabilities = false
        } else if !trimmed.isEmpty {
            if let _ = currentMember {
                // Inside a nested member (parameter/output)
                currentMember?[elementName] = trimmed
            } else if inCapabilities && elementName == "member" {
                // This won't be reached since member is handled above;
                // capabilities values come as leaf text
            } else if inCapabilities {
                capabilities.append(trimmed)
            } else if memberDepth == 1 {
                // Top-level stack field
                stackFields[elementName] = trimmed
            }
        }

        elementStack.removeLast()
        currentText = ""
    }
}
