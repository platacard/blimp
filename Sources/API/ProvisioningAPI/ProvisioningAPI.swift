import OpenAPIRuntime
import OpenAPIURLSession
import JWTProvider
import Cronista
import Auth

public struct ProvisioningAPI {
    
    private let jwtProvider: any JWTProviding
    private let client: any APIProtocol
    private let logger = Cronista(module: "blimp", category: "ProvisioningAPI")
    
    public init(jwtProvider: any JWTProviding) {
        self.jwtProvider = jwtProvider
        
        self.client = Client(
            serverURL: try! Servers.Server1.url(),
            configuration: .init(dateTranscoder: .iso8601WithFractionalSeconds),
            transport: URLSessionTransport(),
            middlewares: [
                AuthMiddleware { try jwtProvider.token() }
            ]
        )
    }
}

