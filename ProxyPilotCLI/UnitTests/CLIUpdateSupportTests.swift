import Foundation
import ProxyPilotCore
import Testing
@testable import proxypilot

@Suite("CLI updater support")
struct CLIUpdateSupportTests {
    private let artifact = Data("trusted update payload".utf8)
    private let publicKey = "96eXhImbqhLRMXaxXcGfvaU1G9SzcEyD4277btP6Eyc="
    private let signature = "Jz0na7TYelfsafCBvJQuP8QFKWN81GsykvGhoRo+Vul0Pn10Agvsy0qhHZAKEHnPEU+J8CpxuBgF5+OViyMGCw=="
    private let sha256 = "ab460ac9e573b9f9cb5d0acc6dbeccdb23b639799d3e8fc35abb969b8ec8bc00"

    @Test func manifestSelectsExactAuthenticatedRelease() throws {
        let manifestJSON = """
        {
          "latest": "1.13.3",
          "versions": [
            {
              "version": "1.13.3",
              "sha256_cli": "\(sha256)",
              "ed_signature_cli": "\(signature)"
            }
          ]
        }
        """
        let manifest = try JSONDecoder().decode(CLIUpdateManifest.self, from: Data(manifestJSON.utf8))

        let release = try manifest.release(for: "1.13.3")
        #expect(release.version == "1.13.3")
        #expect(release.sha256CLI == sha256)
        #expect(release.edSignatureCLI == signature)
    }

    @Test func manifestFailsClosedWhenReleaseOrSignatureIsMissing() throws {
        let unsignedJSON = """
        {
          "latest": "1.13.3",
          "versions": [
            {"version": "1.13.3", "sha256_cli": "\(sha256)"}
          ]
        }
        """
        let manifest = try JSONDecoder().decode(CLIUpdateManifest.self, from: Data(unsignedJSON.utf8))

        #expect(throws: CLIUpdateSupportError.integrityMetadataMissing("1.13.3")) {
            try manifest.release(for: "1.13.3")
        }
        #expect(throws: CLIUpdateSupportError.versionMissing("9.9.9")) {
            try manifest.release(for: "9.9.9")
        }
    }

    @Test func verifiedArtifactIsStagedExecutable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("proxypilot-updater-test-\(UUID().uuidString)")
        let destination = directory.appendingPathComponent("proxypilot")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try CLIUpdateArtifactStager.stage(
            data: artifact,
            release: release,
            at: destination,
            publicKeyBase64: publicKey
        )

        #expect(try Data(contentsOf: destination) == artifact)
        let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o755)
    }

    @Test func tamperedArtifactNeverReachesStagingPath() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("proxypilot-updater-test-\(UUID().uuidString)")
        let destination = directory.appendingPathComponent("proxypilot")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(throws: UpdateArtifactVerifier.VerificationError.self) {
            try CLIUpdateArtifactStager.stage(
                data: Data("tampered update payload".utf8),
                release: release,
                at: destination,
                publicKeyBase64: publicKey
            )
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    private var release: CLIUpdateRelease {
        CLIUpdateRelease(
            version: "1.13.3",
            sha256CLI: sha256,
            edSignatureCLI: signature
        )
    }
}
