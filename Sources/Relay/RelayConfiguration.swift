import Foundation
import Logging

enum SinkKind: String, CaseIterable, Sendable {
    case log
    case forward
    case gitlabPipelineTrigger = "gitlab-pipeline-trigger"
}

struct GitLabSinkConfiguration: Sendable {
    let baseURL: String
    let projectId: String
    let apiToken: String
    let triggerToken: String
    let pendingPackageName: String
    let alertWebhookURL: String?
    let extraTriggerVariables: [String: String]
}

enum ConfiguredSink: Sendable {
    case log
    case forward(url: String)
    case gitlabPipelineTrigger(GitLabSinkConfiguration)
}

struct RelayConfiguration: Sendable {

    let host: String
    let port: Int
    let logLevel: Logger.Level
    let secrets: [String]
    let sinks: [ConfiguredSink]
}

enum RelayConfigurationError: Error, CustomStringConvertible, Equatable {
    case missingSecret
    case invalidPort(String)
    case unknownSink(String)
    case emptySinkList
    case missingVariable(String, hint: String)
    case malformedExtraTriggerVariables(String)

    var description: String {
        switch self {
        case .missingSecret:
            return "ASC_WEBHOOK_SECRET is not set. The relay refuses to start without a webhook secret, otherwise it could not verify deliveries."
        case .invalidPort(let value):
            return "PORT must be an integer in 1...65535, got '\(value)'."
        case .unknownSink(let name):
            let known = SinkKind.allCases.map(\.rawValue).joined(separator: ", ")
            return "Unknown sink '\(name)' in SINKS. Known sinks: \(known)."
        case .emptySinkList:
            let known = SinkKind.allCases.map(\.rawValue).joined(separator: ", ")
            return "SINKS is set but resolves to an empty list. Unset it to get the default 'log' sink, or list at least one of: \(known)."
        case .missingVariable(let name, let hint):
            return "\(name) is not set. \(hint)"
        case .malformedExtraTriggerVariables(let entry):
            return "EXTRA_TRIGGER_VARIABLES entry '\(entry)' is malformed, expected comma-separated key=value pairs."
        }
    }
}

extension RelayConfiguration {

    static let defaultPort = 13100

    static func load(from environment: [String: String]) throws -> RelayConfiguration {
        let secrets = [
            environment["ASC_WEBHOOK_SECRET"],
            environment["ASC_WEBHOOK_SECRET_SECONDARY"]
        ].compactMap { $0 }.filter { !$0.isEmpty }

        guard !secrets.isEmpty else {
            throw RelayConfigurationError.missingSecret
        }

        let port = try parsePort(environment["PORT"])
        let logLevel = environment["LOG_LEVEL"]
            .flatMap { Logger.Level(rawValue: $0.lowercased()) } ?? .info
        let sinks = try parseSinks(environment["SINKS"]).map { kind -> ConfiguredSink in
            switch kind {
            case .log:
                return .log
            case .forward:
                return .forward(url: try require(
                    "FORWARD_URL",
                    in: environment,
                    hint: "The forward sink needs a URL to POST deliveries to."
                ))
            case .gitlabPipelineTrigger:
                return .gitlabPipelineTrigger(try loadGitLabConfiguration(from: environment))
            }
        }

        return RelayConfiguration(
            host: "0.0.0.0",
            port: port,
            logLevel: logLevel,
            secrets: secrets,
            sinks: sinks
        )
    }

    private static func parsePort(_ rawValue: String?) throws -> Int {
        guard let rawValue, !rawValue.isEmpty else {
            return defaultPort
        }
        guard let port = Int(rawValue), (1...65535).contains(port) else {
            throw RelayConfigurationError.invalidPort(rawValue)
        }
        return port
    }

    private static func parseSinks(_ rawValue: String?) throws -> [SinkKind] {
        guard let rawValue, !rawValue.isEmpty else {
            return [.log]
        }
        let kinds = try rawValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { name in
                guard let kind = SinkKind(rawValue: name.lowercased()) else {
                    throw RelayConfigurationError.unknownSink(name)
                }
                return kind
            }
        guard !kinds.isEmpty else {
            // An explicitly set SINKS that resolves to nothing (e.g. ",") would
            // make the relay 200-acknowledge every delivery without processing it.
            throw RelayConfigurationError.emptySinkList
        }
        return kinds
    }

    private static func loadGitLabConfiguration(from environment: [String: String]) throws -> GitLabSinkConfiguration {
        let hint = "Required by the gitlab-pipeline-trigger sink."
        return GitLabSinkConfiguration(
            baseURL: try require("GITLAB_BASE_URL", in: environment, hint: hint),
            projectId: try require("GITLAB_PROJECT_ID", in: environment, hint: hint),
            apiToken: try require("GITLAB_API_TOKEN", in: environment, hint: hint),
            triggerToken: try require("GITLAB_TRIGGER_TOKEN", in: environment, hint: hint),
            pendingPackageName: environment["PENDING_PACKAGE_NAME"] ?? "tf-pending",
            alertWebhookURL: environment["ALERT_WEBHOOK_URL"],
            extraTriggerVariables: try parseExtraTriggerVariables(environment["EXTRA_TRIGGER_VARIABLES"])
        )
    }

    private static func parseExtraTriggerVariables(_ rawValue: String?) throws -> [String: String] {
        guard let rawValue, !rawValue.isEmpty else {
            return [:]
        }
        var variables = [String: String]()
        for entry in rawValue.split(separator: ",") {
            let trimmed = entry.trimmingCharacters(in: .whitespaces)
            guard let separatorIndex = trimmed.firstIndex(of: "=") else {
                throw RelayConfigurationError.malformedExtraTriggerVariables(trimmed)
            }
            let key = String(trimmed[..<separatorIndex]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: separatorIndex)...])
            guard !key.isEmpty else {
                throw RelayConfigurationError.malformedExtraTriggerVariables(trimmed)
            }
            variables[key] = value
        }
        return variables
    }

    private static func require(_ name: String, in environment: [String: String], hint: String) throws -> String {
        guard let value = environment[name], !value.isEmpty else {
            throw RelayConfigurationError.missingVariable(name, hint: hint)
        }
        return value
    }
}
