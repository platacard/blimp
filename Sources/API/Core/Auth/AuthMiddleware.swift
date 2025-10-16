import Foundation
import OpenAPIRuntime
import HTTPTypes

/// A client middleware that injects a value into the `Authorization` header field of the request.
package struct AuthMiddleware {

    /// The value for the `Authorization` header field.
    private let token: @Sendable () throws -> String

    /// Creates a new middleware.
    /// - Parameter value: The value for the `Authorization` header field.
    package init(token: @escaping @Sendable () throws -> String) {
        self.token = token
    }
}

extension AuthMiddleware: ClientMiddleware {
    package func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        request.headerFields[.authorization] = try token()
        return try await next(request, body, baseURL)
    }
}
