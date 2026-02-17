import Foundation

final class Route53ResolverService: LocalStackService {
    // MARK: - Resolver Endpoint Operations

    func listResolverEndpoints() async throws -> [ResolverEndpoint] {
        var allEndpoints: [ResolverEndpoint] = []
        var nextToken: String?

        repeat {
            var payload: [String: Any] = [:]
            if let token = nextToken {
                payload["NextToken"] = token
            }
            let data = try await client.route53ResolverRequest(action: "ListResolverEndpoints", payload: payload)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                break
            }
            if let endpoints = json["ResolverEndpoints"] as? [[String: Any]] {
                allEndpoints.append(contentsOf: endpoints.map { ResolverEndpoint(from: $0) })
            }
            nextToken = json["NextToken"] as? String
        } while nextToken != nil

        return allEndpoints
    }

    func getResolverEndpoint(id: String) async throws -> ResolverEndpoint {
        let data = try await client.route53ResolverRequest(
            action: "GetResolverEndpoint",
            payload: ["ResolverEndpointId": id]
        )
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let endpoint = json["ResolverEndpoint"] as? [String: Any] else {
            throw LocalStackClientError.invalidURL
        }
        return ResolverEndpoint(from: endpoint)
    }

    func listResolverEndpointIpAddresses(endpointId: String) async throws -> [ResolverIpAddress] {
        var allAddresses: [ResolverIpAddress] = []
        var nextToken: String?

        repeat {
            var payload: [String: Any] = ["ResolverEndpointId": endpointId]
            if let token = nextToken {
                payload["NextToken"] = token
            }
            let data = try await client.route53ResolverRequest(action: "ListResolverEndpointIpAddresses", payload: payload)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                break
            }
            if let addresses = json["IpAddresses"] as? [[String: Any]] {
                allAddresses.append(contentsOf: addresses.map { ResolverIpAddress(from: $0) })
            }
            nextToken = json["NextToken"] as? String
        } while nextToken != nil

        return allAddresses
    }

    func createResolverEndpoint(
        name: String,
        direction: String,
        securityGroupIds: [String],
        ipAddresses: [(subnetId: String, ip: String?)]
    ) async throws {
        let ipPayload: [[String: Any]] = ipAddresses.map { addr in
            var entry: [String: Any] = ["SubnetId": addr.subnetId]
            if let ip = addr.ip, !ip.isEmpty {
                entry["Ip"] = ip
            }
            return entry
        }
        let payload: [String: Any] = [
            "CreatorRequestId": UUID().uuidString,
            "Name": name,
            "Direction": direction,
            "SecurityGroupIds": securityGroupIds,
            "IpAddresses": ipPayload,
        ]
        _ = try await client.route53ResolverRequest(action: "CreateResolverEndpoint", payload: payload)
    }

    func deleteResolverEndpoint(id: String) async throws {
        _ = try await client.route53ResolverRequest(
            action: "DeleteResolverEndpoint",
            payload: ["ResolverEndpointId": id]
        )
    }

    // MARK: - Resolver Rule Operations

    func listResolverRules() async throws -> [ResolverRule] {
        var allRules: [ResolverRule] = []
        var nextToken: String?

        repeat {
            var payload: [String: Any] = [:]
            if let token = nextToken {
                payload["NextToken"] = token
            }
            let data = try await client.route53ResolverRequest(action: "ListResolverRules", payload: payload)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                break
            }
            if let rules = json["ResolverRules"] as? [[String: Any]] {
                allRules.append(contentsOf: rules.map { ResolverRule(from: $0) })
            }
            nextToken = json["NextToken"] as? String
        } while nextToken != nil

        return allRules
    }

    func getResolverRule(id: String) async throws -> ResolverRule {
        let data = try await client.route53ResolverRequest(
            action: "GetResolverRule",
            payload: ["ResolverRuleId": id]
        )
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rule = json["ResolverRule"] as? [String: Any] else {
            throw LocalStackClientError.invalidURL
        }
        return ResolverRule(from: rule)
    }

    func createResolverRule(
        name: String,
        ruleType: String,
        domainName: String,
        resolverEndpointId: String?,
        targetIps: [(ip: String, port: Int)]
    ) async throws {
        var payload: [String: Any] = [
            "CreatorRequestId": UUID().uuidString,
            "Name": name,
            "RuleType": ruleType,
            "DomainName": domainName,
        ]
        if let endpointId = resolverEndpointId, !endpointId.isEmpty {
            payload["ResolverEndpointId"] = endpointId
        }
        if !targetIps.isEmpty {
            payload["TargetIps"] = targetIps.map { ["Ip": $0.ip, "Port": $0.port] as [String: Any] }
        }
        _ = try await client.route53ResolverRequest(action: "CreateResolverRule", payload: payload)
    }

    func deleteResolverRule(id: String) async throws {
        _ = try await client.route53ResolverRequest(
            action: "DeleteResolverRule",
            payload: ["ResolverRuleId": id]
        )
    }

    // MARK: - Rule Association Operations

    func listResolverRuleAssociations() async throws -> [ResolverRuleAssociation] {
        var allAssociations: [ResolverRuleAssociation] = []
        var nextToken: String?

        repeat {
            var payload: [String: Any] = [:]
            if let token = nextToken {
                payload["NextToken"] = token
            }
            let data = try await client.route53ResolverRequest(action: "ListResolverRuleAssociations", payload: payload)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                break
            }
            if let assocs = json["ResolverRuleAssociations"] as? [[String: Any]] {
                allAssociations.append(contentsOf: assocs.map { ResolverRuleAssociation(from: $0) })
            }
            nextToken = json["NextToken"] as? String
        } while nextToken != nil

        return allAssociations
    }

    func associateResolverRule(ruleId: String, name: String, vpcId: String) async throws {
        _ = try await client.route53ResolverRequest(
            action: "AssociateResolverRule",
            payload: [
                "ResolverRuleId": ruleId,
                "Name": name,
                "VPCId": vpcId,
            ]
        )
    }

    func disassociateResolverRule(ruleId: String, vpcId: String) async throws {
        _ = try await client.route53ResolverRequest(
            action: "DisassociateResolverRule",
            payload: [
                "ResolverRuleId": ruleId,
                "VPCId": vpcId,
            ]
        )
    }
}
