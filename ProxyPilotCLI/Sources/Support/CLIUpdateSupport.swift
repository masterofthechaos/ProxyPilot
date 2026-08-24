import Foundation
import ProxyPilotCore

struct CLIUpdateManifest: Decodable {
    let latest: String
    let versions: [CLIUpdateRelease]

    func release(for version: String) throws -> CLIUpdateRelease {
        guard let release = versions.first(where: { $0.version == version }) else {
            throw CLIUpdateSupportError.versionMissing(version)
        }
        guard !release.sha256CLI.isEmpty, !release.edSignatureCLI.isEmpty else {
            throw CLIUpdateSupportError.integrityMetadataMissing(version)
        }
        return release
    }
}

struct CLIUpdateRelease: Decodable, Equatable {
    let version: String
    let sha256CLI: String
    let edSignatureCLI: String

    enum CodingKeys: String, CodingKey {
        case version
        case sha256CLI = "sha256_cli"
        case edSignatureCLI = "ed_signature_cli"
    }

    init(version: String, sha256CLI: String, edSignatureCLI: String) {
        self.version = version
        self.sha256CLI = sha256CLI
        self.edSignatureCLI = edSignatureCLI
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(String.self, forKey: .version)
        // Keep `update --check` compatible with legacy manifests while making
        // installation fail closed in `release(for:)` when either field is absent.
        sha256CLI = try container.decodeIfPresent(String.self, forKey: .sha256CLI) ?? ""
        edSignatureCLI = try container.decodeIfPresent(String.self, forKey: .edSignatureCLI) ?? ""
    }
}

enum CLIUpdateSupportError: LocalizedError, Equatable {
    case versionMissing(String)
    case integrityMetadataMissing(String)
    case emptyDownload

    var errorDescription: String? {
        switch self {
        case .versionMissing(let version):
            return "Version \(version) has no release entry in the update manifest."
        case .integrityMetadataMissing(let version):
            return "Version \(version) is missing sha256_cli or ed_signature_cli metadata."
        case .emptyDownload:
            return "Downloaded file was empty."
        }
    }
}

enum CLIUpdateArtifactStager {
    static func stage(
        data: Data,
        release: CLIUpdateRelease,
        at destinationURL: URL,
        publicKeyBase64: String = UpdateArtifactVerifier.proxyPilotPublicKeyBase64
    ) throws {
        guard !data.isEmpty else {
            throw CLIUpdateSupportError.emptyDownload
        }

        // Authenticate the bytes before writing or marking anything executable.
        try UpdateArtifactVerifier.verify(
            data: data,
            expectedSHA256: release.sha256CLI,
            signatureBase64: release.edSignatureCLI,
            publicKeyBase64: publicKeyBase64
        )

        try data.write(to: destinationURL, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: destinationURL.path
        )
    }
}
