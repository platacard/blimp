import XCTest
@testable import WebhookKit
import Crypto
import Foundation

final class SignatureVerifierTests: XCTestCase {

    private let body = Data(#"{"data":{"type":"webhookPingCreated"}}"#.utf8)
    private let secret = "whsec_test_secret"

    /// HMAC-SHA256 of `body` with `secret`, precomputed with `openssl dgst -sha256 -hmac`.
    private let knownHexDigest = "065ca525b541f6b77e8eea867abdac3cc108ab11010d2956395853d51cea073b"

    private func computedHexDigest(body: Data, secret: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: body, using: key)
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Valid signatures

    func testVerifiesKnownVector() {
        let verifier = SignatureVerifier(secrets: [secret])

        XCTAssertTrue(verifier.verify(rawBody: body, signatureHeader: "hmacsha256=\(knownHexDigest)"))
        XCTAssertEqual(computedHexDigest(body: body, secret: secret), knownHexDigest)
    }

    func testVerifiesComputedSignatureForArbitraryBody() {
        let body = Data("hello webhook body".utf8)
        let verifier = SignatureVerifier(secrets: ["primary-secret"])
        let digest = computedHexDigest(body: body, secret: "primary-secret")

        XCTAssertTrue(verifier.verify(rawBody: body, signatureHeader: "hmacsha256=\(digest)"))
    }

    func testToleratesUppercaseHex() {
        let verifier = SignatureVerifier(secrets: [secret])

        XCTAssertTrue(verifier.verify(rawBody: body, signatureHeader: "hmacsha256=\(knownHexDigest.uppercased())"))
    }

    func testToleratesUppercasePrefixAndWhitespace() {
        let verifier = SignatureVerifier(secrets: [secret])

        XCTAssertTrue(verifier.verify(rawBody: body, signatureHeader: "  HMACSHA256=\(knownHexDigest) "))
    }

    // MARK: - Secret rotation

    func testVerifiesAgainstSecondarySecret() {
        let body = Data("hello webhook body".utf8)
        let verifier = SignatureVerifier(secrets: ["primary-secret", "secondary-secret"])
        let signedWithSecondary = computedHexDigest(body: body, secret: "secondary-secret")

        XCTAssertTrue(verifier.verify(rawBody: body, signatureHeader: "hmacsha256=\(signedWithSecondary)"))
    }

    func testVerifiesAgainstPrimaryWhenSecondaryConfigured() {
        let body = Data("hello webhook body".utf8)
        let verifier = SignatureVerifier(secrets: ["primary-secret", "secondary-secret"])
        let signedWithPrimary = computedHexDigest(body: body, secret: "primary-secret")

        XCTAssertTrue(verifier.verify(rawBody: body, signatureHeader: "hmacsha256=\(signedWithPrimary)"))
    }

    // MARK: - Rejections

    func testRejectsTamperedBody() {
        let verifier = SignatureVerifier(secrets: [secret])
        let tampered = Data(#"{"data":{"type":"somethingElse"}}"#.utf8)

        XCTAssertFalse(verifier.verify(rawBody: tampered, signatureHeader: "hmacsha256=\(knownHexDigest)"))
    }

    func testRejectsWrongSecret() {
        let verifier = SignatureVerifier(secrets: ["a-different-secret"])

        XCTAssertFalse(verifier.verify(rawBody: body, signatureHeader: "hmacsha256=\(knownHexDigest)"))
    }

    func testRejectsMissingHeader() {
        let verifier = SignatureVerifier(secrets: [secret])

        XCTAssertFalse(verifier.verify(rawBody: body, signatureHeader: nil))
    }

    func testRejectsHeaderWithoutPrefix() {
        let verifier = SignatureVerifier(secrets: [secret])

        XCTAssertFalse(verifier.verify(rawBody: body, signatureHeader: knownHexDigest))
        XCTAssertFalse(verifier.verify(rawBody: body, signatureHeader: "sha256=\(knownHexDigest)"))
    }

    func testRejectsMalformedHex() {
        let verifier = SignatureVerifier(secrets: [secret])

        XCTAssertFalse(verifier.verify(rawBody: body, signatureHeader: "hmacsha256=zzzz"))
        XCTAssertFalse(verifier.verify(rawBody: body, signatureHeader: "hmacsha256=abc"))
        XCTAssertFalse(verifier.verify(rawBody: body, signatureHeader: "hmacsha256="))
    }

    func testRejectsEverythingWithoutConfiguredSecrets() {
        let verifier = SignatureVerifier(secrets: [])

        XCTAssertFalse(verifier.verify(rawBody: body, signatureHeader: "hmacsha256=\(knownHexDigest)"))
    }

    // MARK: - Digest length

    func testRejectsTruncatedDigest() {
        let verifier = SignatureVerifier(secrets: [secret])
        let truncated = String(knownHexDigest.dropLast(2))

        XCTAssertFalse(verifier.verify(rawBody: body, signatureHeader: "hmacsha256=\(truncated)"))
    }

    func testRejectsOverlongDigest() {
        let verifier = SignatureVerifier(secrets: [secret])

        XCTAssertFalse(verifier.verify(rawBody: body, signatureHeader: "hmacsha256=\(knownHexDigest)00"))
    }

    func testRejectsWhitespaceInsideDigest() {
        let verifier = SignatureVerifier(secrets: [secret])
        let split = knownHexDigest.prefix(10) + " " + knownHexDigest.dropFirst(10)

        XCTAssertFalse(verifier.verify(rawBody: body, signatureHeader: "hmacsha256=\(split)"))
    }

    func testRejectsSpaceBeforeEqualsSign() {
        let verifier = SignatureVerifier(secrets: [secret])

        XCTAssertFalse(verifier.verify(rawBody: body, signatureHeader: "hmacsha256 =\(knownHexDigest)"))
    }

    // MARK: - Secret configuration

    func testIgnoresEmptySecrets() {
        let header = "hmacsha256=\(knownHexDigest)"

        XCTAssertFalse(SignatureVerifier(secrets: [""]).verify(rawBody: body, signatureHeader: header))
        XCTAssertTrue(SignatureVerifier(secrets: ["", secret]).verify(rawBody: body, signatureHeader: header))
    }

    func testRejectsWhenNoConfiguredSecretMatches() {
        let verifier = SignatureVerifier(secrets: ["one", "two", "three"])

        XCTAssertFalse(verifier.verify(rawBody: body, signatureHeader: "hmacsha256=\(knownHexDigest)"))
    }

    // MARK: - Body handling

    func testSignsExactBytesIncludingBinaryAndUnicode() {
        var body = Data("{\"name\":\"Ünïcødé 🚀\"}".utf8)
        body.append(0)
        let verifier = SignatureVerifier(secrets: [secret])
        let header = "hmacsha256=\(computedHexDigest(body: body, secret: secret))"

        XCTAssertTrue(verifier.verify(rawBody: body, signatureHeader: header))
        XCTAssertFalse(verifier.verify(rawBody: body + Data("\n".utf8), signatureHeader: header))
        XCTAssertFalse(verifier.verify(rawBody: body.dropLast(), signatureHeader: header))
    }

    func testVerifiesEmptyBody() {
        let verifier = SignatureVerifier(secrets: [secret])
        let header = "hmacsha256=\(computedHexDigest(body: Data(), secret: secret))"

        XCTAssertTrue(verifier.verify(rawBody: Data(), signatureHeader: header))
        XCTAssertFalse(verifier.verify(rawBody: body, signatureHeader: header))
    }

    func testAcceptsAnyDataProtocolBody() {
        let verifier = SignatureVerifier(secrets: [secret])
        let header = "hmacsha256=\(knownHexDigest)"

        XCTAssertTrue(verifier.verify(rawBody: Array(body), signatureHeader: header))
        XCTAssertTrue(verifier.verify(rawBody: body[body.startIndex...], signatureHeader: header))
    }
}
