import OpenAPIURLSession
import OpenAPIRuntime
import Foundation
import HTTPTypes
import Cronista

public final actor RetryingURLSessionTransport: ClientTransport {

    private let env: [String: String] = ProcessInfo.processInfo.environment
    private let transport: ClientTransport
    private let logger: Cronista

    private var retryCount = 0

    public init(
        underlyingTransport: ClientTransport = URLSessionTransport(),
        logger: Cronista = Cronista(
            module: "blimp",
            category: "RetryingURLSessionTransport",
            isFileLoggingEnabled: true
        )
    ) {
        self.transport = underlyingTransport
        self.logger = logger
    }

    public func send(_ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String) async throws -> (HTTPResponse, HTTPBody?) {
        logger.info("✈️ Sending request: \(request) with body: \(String(describing: body)), baseURL: \(baseURL), operationID: \(operationID)")

        do {
            let result = try await transport.send(request, body: body, baseURL: baseURL, operationID: operationID)

            if result.0.status == 500 {
                return try await retry(request, body, baseURL, operationID, error: TransportError.received500)
            }
            
            logger.info("✈️ Received result: response: \(result.0), body: \(String(describing: result.1.debugDescription))")
            retryCount = 0

            return result
        } catch {
            return try await retry(request, body, baseURL, operationID, error: error)
        }
    }
}

// MARK: - Private

private extension RetryingURLSessionTransport {

    func retry(
        _ request: HTTPRequest,
        _ body: HTTPBody?,
        _ baseURL: URL,
        _ operationID: String,
        error: Error
    ) async throws -> (HTTPResponse, HTTPBody?) {
        logger.error("✈️ Attempt \(retryCount) failed with error: \(error)")

        guard retryCount < 3 else {
            logger.error("✈️ Retrying failed 3 times")
            throw TransportError.retryingFailed
        }

        retryCount += 1
        let retryIntervalSec = 5 * retryCount

        logger.warning("✈️ Retrying after \(retryIntervalSec)s...")
        try await Task.sleep(for: .seconds(retryIntervalSec))
        logger.warning("✈️ Retrying now...")

        return try await send(request, body: body, baseURL: baseURL, operationID: operationID)
    }
}

private extension RetryingURLSessionTransport {
    
    enum TransportError: LocalizedError {
        case retryingFailed
        case received500

        var description: String {
            switch self {
            case .retryingFailed: "✈️ Retrying failed 3 times. No luck today"
            case .received500: "✈️ 500 status received"
            }
        }
    }
}
