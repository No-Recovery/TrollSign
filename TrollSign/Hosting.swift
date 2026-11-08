import Foundation

// MARK: - Hosting provider

enum HostingProvider: String, CaseIterable, Identifiable {
    case ready
    case github

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ready:  return "Ready hosting"
        case .github: return "GitHub hosting"
        }
    }

    var detail: String {
        switch self {
        case .ready:
            return "Zero setup. The signed IPA and its install manifest are uploaded to a public HTTPS host automatically."
        case .github:
            return "Publish to your own repository: GitHub Releases for the IPA, GitHub Pages for the manifest."
        }
    }
}

enum HostingConfig {
    static let providerKey = "hostingProvider"

    static var provider: HostingProvider {
        HostingProvider(rawValue: UserDefaults.standard.string(forKey: providerKey) ?? "") ?? .ready
    }

    static var statusText: String {
        switch provider {
        case .ready:
            return "Ready · no setup"
        case .github:
            return GitHubHostingConfig.isConfigured
                ? "GitHub · \(GitHubHostingConfig.owner)/\(GitHubHostingConfig.repo)"
                : "GitHub · token required"
        }
    }

    static var installPage: URL? {
        switch provider {
        case .ready:
            return URL(string: "https://no-recovery.github.io/TrollSign/")
        case .github:
            return GitHubHostingConfig.installPage
        }
    }
}

// MARK: - Zero-setup hosting (catbox.moe)

/// Anonymous, permanent, HTTPS file hosting. No account or token, so installs
/// work immediately after a fresh install of TrollSign.
enum ReadyHosting {
    private static let endpoint = URL(string: "https://catbox.moe/user/api.php")!
    private static let maxBytes: Int64 = 200 * 1024 * 1024

    struct Error: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func publish(ipa: URL, entry: IPAEntry) async throws -> URL {
        let attributes = try? FileManager.default.attributesOfItem(atPath: ipa.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        if size > maxBytes {
            throw Error(message: "This IPA is larger than 200 MB. Switch to GitHub hosting in Settings → Hosting for large files.")
        }

        let ipaURL = try await upload(file: ipa,
                                      filename: "TrollSign-\(UUID().uuidString).ipa",
                                      mime: "application/octet-stream")

        let manifest = LocalServer.manifest(ipaURL: ipaURL.absoluteString,
                                            bundleID: entry.bundleID,
                                            version: entry.version,
                                            title: entry.name)
        return try await upload(data: Data(manifest.utf8),
                                filename: "TrollSign-\(UUID().uuidString).xml",
                                mime: "text/xml")
    }

    static func test() async -> String {
        var request = URLRequest(url: URL(string: "https://catbox.moe/")!)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 20
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
                return "Ready hosting is not reachable right now (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0))."
            }
            return "Ready — no setup required. Uploads go to catbox.moe over HTTPS."
        } catch {
            return "Ready hosting is not reachable: \(error.localizedDescription)"
        }
    }

    // MARK: Upload

    private static func upload(data: Data, filename: String, mime: String) async throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrollSign-ready-\(UUID().uuidString)")
        try data.write(to: tmp, options: .atomic)
        defer { try? FileManager.default.removeItem(at: tmp) }
        return try await upload(file: tmp, filename: filename, mime: mime)
    }

    private static func upload(file: URL, filename: String, mime: String) async throws -> URL {
        let boundary = "TrollSign-\(UUID().uuidString)"
        let body = try await Task.detached(priority: .userInitiated) {
            try makeMultipart(file: file, filename: filename, mime: mime, boundary: boundary)
        }.value

        defer { try? FileManager.default.removeItem(at: body) }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("TrollSign/2.3 (iOS)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.upload(for: request, fromFile: body)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: text), url.scheme == "https" else {
            let text = String(data: data, encoding: .utf8) ?? "unknown error"
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw Error(message: "Ready hosting upload failed (HTTP \(code)): \(text.prefix(160))")
        }
        return url
    }

    private static func makeMultipart(file: URL, filename: String, mime: String,
                                      boundary: String) throws -> URL {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrollSign-body-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: out.path, contents: nil) else {
            throw Error(message: "Cannot create the upload body.")
        }

        let handle = try FileHandle(forWritingTo: out)
        do {
            try handle.write(contentsOf: Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"reqtype\"\r\n\r\nfileupload\r\n".utf8))
            try handle.write(contentsOf: Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"fileToUpload\"; filename=\"\(filename)\"\r\nContent-Type: \(mime)\r\n\r\n".utf8))

            let input = try FileHandle(forReadingFrom: file)
            while let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty {
                try handle.write(contentsOf: chunk)
            }
            try input.close()

            try handle.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
            try handle.close()
            return out
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: out)
            throw error
        }
    }
}
