import AsyncHTTPClient
import Foundation
import Hummingbird
import Logging
import WebhookKit

@main
struct RelayMain {

    static func main() async throws {
        let configuration: RelayConfiguration
        do {
            configuration = try RelayConfiguration.load(from: ProcessInfo.processInfo.environment)
        } catch {
            FileHandle.standardError.write(Data("blimp-relay: \(error)\n".utf8))
            exit(1)
        }

        var logger = Logger(label: "blimp-relay")
        logger.logLevel = configuration.logLevel

        let httpClient = HTTPClient(eventLoopGroupProvider: .singleton)

        let verifier = SignatureVerifier(secrets: configuration.secrets)
        let sinks = SinkFactory.makeSinks(
            configuration: configuration,
            httpClient: httpClient,
            logger: logger
        )
        let router = RelayRouter.build(verifier: verifier, sinks: sinks, logger: logger)

        let app = Application(
            router: router,
            configuration: .init(
                address: .hostname(configuration.host, port: configuration.port),
                serverName: "blimp-relay"
            ),
            logger: logger
        )

        logger.info("Starting blimp-relay", metadata: [
            "host": .string(configuration.host),
            "port": .string(String(configuration.port)),
            "sinks": .string(sinks.map(\.name).joined(separator: ","))
        ])

        do {
            try await app.runService()
        } catch {
            try? await httpClient.shutdown()
            throw error
        }
        try await httpClient.shutdown()
    }
}
