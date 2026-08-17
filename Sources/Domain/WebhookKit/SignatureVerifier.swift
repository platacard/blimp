import Crypto
import Foundation

/// Verifies App Store Connect webhook signatures.
///
/// Apple signs every delivery with HMAC-SHA256 over the raw request body and sends the
/// result in the `x-apple-signature` header as `hmacsha256=<hex digest>`.
/// Multiple secrets are supported so the secret can be rotated without dropping deliveries.
public struct SignatureVerifier: Sendable {

    private let keys: [SymmetricKey]

    public init(secrets: [String]) {
        self.keys = secrets
            .filter { !$0.isEmpty }
            .map { SymmetricKey(data: Foundation.Data($0.utf8)) }
    }

    /// Verifies the signature header against the raw request body.
    ///
    /// Returns `false` for a missing or malformed header, an invalid signature,
    /// or when no secrets are configured. Never throws.
    public func verify(rawBody: some DataProtocol, signatureHeader: String?) -> Bool {
        guard
            !keys.isEmpty,
            let signatureHeader,
            let signature = Self.parseSignature(signatureHeader)
        else {
            return false
        }

        return keys.contains { key in
            HMAC<SHA256>.isValidAuthenticationCode(signature, authenticating: rawBody, using: key)
        }
    }

    private static func parseSignature(_ header: String) -> Foundation.Data? {
        let trimmed = header.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "hmacsha256="
        guard trimmed.lowercased().hasPrefix(prefix) else {
            return nil
        }
        let hex = trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        return Foundation.Data(hexEncoded: hex)
    }
}

// MARK: - Hex decoding

private extension Foundation.Data {

    init?(hexEncoded string: String) {
        let utf8 = Array(string.utf8)
        guard !utf8.isEmpty, utf8.count.isMultiple(of: 2) else {
            return nil
        }

        var bytes = [UInt8]()
        bytes.reserveCapacity(utf8.count / 2)
        for index in stride(from: 0, to: utf8.count, by: 2) {
            guard let high = utf8[index].hexNibble, let low = utf8[index + 1].hexNibble else {
                return nil
            }
            bytes.append(high << 4 | low)
        }
        self.init(bytes)
    }
}

private extension UInt8 {

    var hexNibble: UInt8? {
        switch self {
        case UInt8(ascii: "0")...UInt8(ascii: "9"):
            return self - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"):
            return self - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"):
            return self - UInt8(ascii: "A") + 10
        default:
            return nil
        }
    }
}
