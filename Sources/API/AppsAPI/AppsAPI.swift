import OpenAPIRuntime
import OpenAPIURLSession
import JWTProvider
import Cronista
import Auth
import ClientTransport

public struct AppsAPI: Sendable {

    private let jwtProvider: any JWTProviding
    private let client: any APIProtocol

    nonisolated(unsafe) private let logger: Cronista

    public init(jwtProvider: any JWTProviding) {
        self.jwtProvider = jwtProvider
        self.logger = Cronista(module: "Blimp", category: "AppsAPI")

        self.client = Client(
            serverURL: try! Servers.Server1.url(),
            configuration: .init(dateTranscoder: .iso8601WithFractionalSeconds),
            transport: RetryingURLSessionTransport(),
            middlewares: [
                AuthMiddleware { try jwtProvider.token() }
            ]
        )
    }
    
    public func getAppId(bundleId: String) async throws -> String {
        let response = try await client.appsGetCollection(
            Operations.AppsGetCollection.Input(
                query: .init(filter_lbrack_bundleId_rbrack_: [bundleId])
            )
        )
        
        guard let appId = try response.ok.body.json.data.first(where: { $0.attributes?.bundleId == bundleId })?.id else {
            throw ServiceError.failedToGetAppId
        }
        
        return appId
    }
}

// MARK: - Extensions

extension AppsAPI {
    enum ServiceError: Error {
        case failedToGetAppId
    }
}
