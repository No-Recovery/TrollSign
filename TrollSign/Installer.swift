import UIKit

/// Installs a signed IPA through the selected hosting provider.
///
/// - `.ready`  — zero-setup anonymous HTTPS host (works immediately).
/// - `.github` — the user's GitHub Releases + Pages (optional).
/// - `.local`  — the built-in HTTPS loopback server, used by Certificates.
enum Installer {
    @MainActor
    static func install(signedIPA: URL, entry: IPAEntry) async throws {
        switch HostingConfig.provider {
        case .ready:
            let manifest = try await ReadyHosting.publish(ipa: signedIPA, entry: entry)
            try await open(manifest: manifest)

        case .github:
            guard GitHubHostingConfig.isConfigured else {
                throw AppError("GitHub hosting needs an access token. Open Settings → Hosting, add a token, or switch to Ready hosting.")
            }
            KeepAlive.shared.start()
            let manifest = try await GitHubHosting.publish(ipa: signedIPA, entry: entry)
            try await open(manifest: manifest)
        }
    }

    /// Used by the Certificates screen to test the localhost.direct server.
    @MainActor
    static func installLocally(signedIPA: URL, entry: IPAEntry) async throws {
        let host = ServerConfig.host
        guard !host.isEmpty else {
            throw AppError("Server host is not set. Long-press the Settings tab → Local Installation Server.")
        }

        try await LocalServer.shared.start()
        let id = entry.id.uuidString
        LocalServer.shared.register(id: id, item: .init(ipa: signedIPA, bundleID: entry.bundleID,
                                                        version: entry.version, title: entry.name))
        KeepAlive.shared.start()

        guard let manifest = URL(string: "https://\(host):\(ServerConfig.port)/\(id).plist") else {
            throw AppError("Bad manifest URL")
        }
        try await open(manifest: manifest)
    }

    private static func open(manifest: URL) async throws {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let encoded = manifest.absoluteString.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        guard let url = URL(string: "itms-services://?action=download-manifest&url=\(encoded)") else {
            throw AppError("Bad manifest URL")
        }
        let ok = await UIApplication.shared.open(url)
        if !ok { throw AppError("iOS refused to open the install link") }
    }
}
