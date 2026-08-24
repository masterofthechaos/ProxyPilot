#if canImport(CryptoKit)
import CryptoKit
#elseif canImport(Crypto)
import Crypto
#endif
import Foundation

/// Verifies CLI update bytes against the same Ed25519 trust root used by
/// Sparkle. Verification is intentionally independent of HTTPS: an attacker
/// who can replace both the manifest and artifact still cannot forge a release.
public enum UpdateArtifactVerifier {
    /// `SUPublicEDKey` from `project.yml`, decoded as a raw Ed25519 public key.
    public static let proxyPilotPublicKeyBase64 = "bLpskbpC2oZ6Hf9NQ1b7E1asQJuWlzGsB8RZCHXC5Zg="

    public enum VerificationError: LocalizedError, Equatable {
        case invalidExpectedSHA256
        case checksumMismatch(expected: String, actual: String)
        case invalidSignatureEncoding
        case invalidPublicKey
        case invalidSignature

        public var errorDescription: String? {
            switch self {
            case .invalidExpectedSHA256:
                return "The manifest contains an invalid CLI SHA-256 value."
            case .checksumMismatch(let expected, let actual):
                return "CLI checksum mismatch (expected \(expected), got \(actual))."
            case .invalidSignatureEncoding:
                return "The manifest contains an invalid CLI Ed25519 signature."
            case .invalidPublicKey:
                return "The embedded CLI update public key is invalid."
            case .invalidSignature:
                return "The CLI update signature is not valid for the downloaded artifact."
            }
        }
    }

    public static func verify(
        data: Data,
        expectedSHA256: String,
        signatureBase64: String,
        publicKeyBase64: String = proxyPilotPublicKeyBase64
    ) throws {
        let normalizedExpected = expectedSHA256.lowercased()
        guard normalizedExpected.count == 64,
              normalizedExpected.allSatisfy({ $0.isHexDigit }) else {
            throw VerificationError.invalidExpectedSHA256
        }

        let actualSHA256 = sha256Hex(of: data)
        guard actualSHA256 == normalizedExpected else {
            throw VerificationError.checksumMismatch(
                expected: normalizedExpected,
                actual: actualSHA256
            )
        }

        guard let signature = Data(base64Encoded: signatureBase64), signature.count == 64 else {
            throw VerificationError.invalidSignatureEncoding
        }
        guard let publicKeyData = Data(base64Encoded: publicKeyBase64), publicKeyData.count == 32,
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData) else {
            throw VerificationError.invalidPublicKey
        }
        guard publicKey.isValidSignature(signature, for: data) else {
            throw VerificationError.invalidSignature
        }
    }

    public static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
