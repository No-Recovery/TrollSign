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

// MARK: - Zero-setup hosting

/// Anonymous HTTPS file hosting. No account or token, so installs work right
/// after a fresh install of TrollSign.
///
/// catbox.moe is tried first (permanent links). If it is rate-limited or
/// blocked, filebin.net (6-day links) is used automatically.
enum ReadyHosting {
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

        var failures: [String] = []
        for backend in Backend.allCases {
            do {
                return try await backend.publish(ipa: ipa, entry: entry)
            } catch {
                failures.append("\(backend.title): \(error.localizedDescription)")
            }
        }

        throw Error(message: "Ready hosting upload failed.\n" + failures.joined(separator: "\n"))
    }

    static func test() async -> String {
        async let catbox = reachable("https://catbox.moe/")
        async let filebin = reachable("https://filebin.net/")
        let (catboxOK, filebinOK) = await (catbox, filebin)

        if filebinOK {
            return "Ready — no setup required. Uploads use catbox.moe with filebin.net as a fallback."
        }
        if catboxOK {
            return "Ready — no setup required. Uploads go to catbox.moe over HTTPS."
        }
        return "Ready hosting is not reachable right now. Check the network connection."
    }

    private static func reachable(_ string: String) async -> Bool {
        guard let url = URL(string: string) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 15
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return (200..<400).contains(http.statusCode)
    }

    // MARK: Backends

    private enum Backend: CaseIterable {
        case catbox
        case filebin

        var title: String {
            switch self {
            case .catbox: return "catbox.moe"
            case .filebin: return "filebin.net"
            }
        }

        func publish(ipa: URL, entry: IPAEntry) async throws -> URL {
            switch self {
            case .catbox:
                return try await catboxPublish(ipa: ipa, entry: entry)
            case .filebin:
                return try await filebinPublish(ipa: ipa, entry: entry)
            }
        }
    }

    // MARK: catbox.moe

    private static func catboxPublish(ipa: URL, entry: IPAEntry) async throws -> URL {
        let ipaURL = try await catboxUpload(file: ipa,
                                            filename: "trollsign-\(UUID().uuidString.lowercased()).ipa",
                                            mime: "application/octet-stream")
        let manifest = LocalServer.manifest(ipaURL: ipaURL.absoluteString,
                                            bundleID: entry.bundleID,
                                            version: entry.version,
                                            title: entry.name)
        return try await catboxUpload(data: Data(manifest.utf8),
                                      filename: "trollsign-\(UUID().uuidString.lowercased()).xml",
                                      mime: "text/xml")
    }

    private static func catboxUpload(data: Data, filename: String, mime: String) async throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrollSign-ready-\(UUID().uuidString)")
        try data.write(to: tmp, options: .atomic)
        defer { try? FileManager.default.removeItem(at: tmp) }
        return try await catboxUpload(file: tmp, filename: filename, mime: mime)
    }

    private static func catboxUpload(file: URL, filename: String, mime: String) async throws -> URL {
        let boundary = "TrollSign-\(UUID().uuidString)"
        let body = try await Task.detached(priority: .userInitiated) {
            try makeCatboxBody(file: file, filename: filename, mime: mime, boundary: boundary)
        }.value
        defer { try? FileManager.default.removeItem(at: body) }

        var request = URLRequest(url: URL(string: "https://catbox.moe/user/api.php")!)
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
            throw Error(message: "catbox upload failed (HTTP \(code)): \(text.prefix(160))")
        }
        return url
    }

    private static func makeCatboxBody(file: URL, filename: String, mime: String,
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

    // MARK: filebin.net

    private static func filebinPublish(ipa: URL, entry: IPAEntry) async throws -> URL {
        let bin = "trollsign-\(UUID().uuidString.lowercased())"
        let ipaName = "trollsign-\(UUID().uuidString.lowercased()).ipa"
        let ipaURL = try await filebinUpload(file: ipa, bin: bin, filename: ipaName,
                                             mime: "application/octet-stream")
        let manifest = LocalServer.manifest(ipaURL: ipaURL.absoluteString,
                                            bundleID: entry.bundleID,
                                            version: entry.version,
                                            title: entry.name)
        return try await filebinUpload(data: Data(manifest.utf8), bin: bin,
                                       filename: "trollsign-\(UUID().uuidString.lowercased()).xml",
                                       mime: "text/xml")
    }

    private static func filebinUpload(data: Data, bin: String, filename: String,
                                      mime: String) async throws -> URL {
        let request = filebinRequest(bin: bin, filename: filename, mime: mime)
        let (body, response) = try await URLSession.shared.upload(for: request, from: data)
        return try validateFilebin(body: body, response: response, request: request)
    }

    private static func filebinUpload(file: URL, bin: String, filename: String,
                                      mime: String) async throws -> URL {
        let request = filebinRequest(bin: bin, filename: filename, mime: mime)
        let (body, response) = try await URLSession.shared.upload(for: request, fromFile: file)
        return try validateFilebin(body: body, response: response, request: request)
    }

    private static func filebinRequest(bin: String, filename: String, mime: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://filebin.net/\(bin)/\(filename)")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 240
        request.setValue(mime, forHTTPHeaderField: "Content-Type")
        request.setValue("TrollSign/2.3 (iOS)", forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func validateFilebin(body: Data, response: URLResponse,
                                        request: URLRequest) throws -> URL {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let text = String(data: body, encoding: .utf8) ?? "unknown error"
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw Error(message: "filebin upload failed (HTTP \(code)): \(text.prefix(160))")
        }
        guard let url = request.url else { throw Error(message: "Bad filebin URL.") }
        return url
    }
}
