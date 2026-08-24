#if canImport(Foundation)
import Foundation
#endif
import Testing
@testable import ProxyPilotCore

@Suite("CLI update artifact verification")
struct UpdateArtifactVerifierTests {
    private let artifact = Data("trusted update payload".utf8)
    private let publicKey = "96eXhImbqhLRMXaxXcGfvaU1G9SzcEyD4277btP6Eyc="
    private let signature = "Jz0na7TYelfsafCBvJQuP8QFKWN81GsykvGhoRo+Vul0Pn10Agvsy0qhHZAKEHnPEU+J8CpxuBgF5+OViyMGCw=="
    private let sha256 = "ab460ac9e573b9f9cb5d0acc6dbeccdb23b639799d3e8fc35abb969b8ec8bc00"

    @Test func acceptsMatchingDigestAndSignature() throws {
        try UpdateArtifactVerifier.verify(
            data: artifact,
            expectedSHA256: sha256,
            signatureBase64: signature,
            publicKeyBase64: publicKey
        )
    }

    @Test func rejectsTamperedArtifactBeforeSignatureAcceptance() {
        #expect(throws: UpdateArtifactVerifier.VerificationError.self) {
            try UpdateArtifactVerifier.verify(
                data: Data("tampered update payload".utf8),
                expectedSHA256: sha256,
                signatureBase64: signature,
                publicKeyBase64: publicKey
            )
        }
    }

    @Test func rejectsSignatureFromDifferentArtifact() {
        let differentArtifact = Data("different but correctly hashed payload".utf8)
        #expect(throws: UpdateArtifactVerifier.VerificationError.invalidSignature) {
            try UpdateArtifactVerifier.verify(
                data: differentArtifact,
                expectedSHA256: UpdateArtifactVerifier.sha256Hex(of: differentArtifact),
                signatureBase64: signature,
                publicKeyBase64: publicKey
            )
        }
    }

    @Test func rejectsMalformedIntegrityMetadata() {
        #expect(throws: UpdateArtifactVerifier.VerificationError.invalidExpectedSHA256) {
            try UpdateArtifactVerifier.verify(
                data: artifact,
                expectedSHA256: "not-a-hash",
                signatureBase64: signature,
                publicKeyBase64: publicKey
            )
        }

        #expect(throws: UpdateArtifactVerifier.VerificationError.invalidSignatureEncoding) {
            try UpdateArtifactVerifier.verify(
                data: artifact,
                expectedSHA256: sha256,
                signatureBase64: "not-base64",
                publicKeyBase64: publicKey
            )
        }
    }
}
