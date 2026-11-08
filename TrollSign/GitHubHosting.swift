import Foundation
import SwiftUI

// MARK: - Configuration

enum GitHubHostingConfig {
    static let defaultOwner = "No-Recovery"
    static let defaultRepo = "TrollSign"

    static var owner: String {
        let v = (UserDefaults.standard.string(forKey: "ghOwner") ?? "").trimmingCharacters(in: .whitespaces)
        return v.isEmpty ? defaultOwner : v
    }
    static var repo: String {
        let v = (UserDefaults.standard.string(forKey: "ghRepo") ?? "").trimmingCharacters(in: .whitespaces)
        return v.isEmpty ? defaultRepo : v
    }
    static var branch: String {
        let v = (UserDefaults.standard.string(forKey: "ghBranch") ?? "").trimmingCharacters(in: .whitespaces)
        return v.isEmpty ? "main" : v
    }
    /// Optional custom domain or a different Pages URL (no trailing slash).
    static var pagesOverride: String {
        (UserDefaults.standard.string(forKey: "ghPagesBase") ?? "").trimmingCharacters(in: .whitespaces)
    }
    static var token: String { Keychain.get("github.token") ?? "" }

    static var isConfigured: Bool { !token.isEmpty && !owner.isEmpty && !repo.isEmpty }

    static var pagesBase: URL? {
        if !pagesOverride.isEmpty, let u = URL(string: pagesOverride) { return u }
        return URL(string: "https://\(owner.lowercased()).github.io/\(repo)/")
    }

    static var installPage: URL? { pagesBase }
}

// MARK: - GitHub API client

enum GitHubHosting {
    struct APIError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Uploads the signed IPA as a release asset, commits a manifest to the
    /// Pages branch and returns the public HTTPS manifest URL. The manifest uses
    /// the .xml extension because GitHub Pages serves .plist as
    /// application/octet-stream, while .xml is served as application/xml.
    static func publish(ipa: URL, entry: IPAEntry) async throws -> URL {
        guard GitHubHostingConfig.isConfigured else {
            throw APIError(message: "GitHub Hosting is on, but the account or token is missing. Open Settings → GitHub Hosting.")
        }

        let owner = GitHubHostingConfig.owner
        let repo = GitHubHostingConfig.repo
        let branch = GitHubHostingConfig.branch
        let token = GitHubHostingConfig.token

        try await ensureRepository(owner: owner, repo: repo, token: token)

        let pages = try await ensurePages(owner: owner, repo: repo, branch: branch, token: token)

        let tag = "ipa-\(Int(Date().timeIntervalSince1970))"
        let release = try await createRelease(owner: owner, repo: repo, token: token,
                                              tag: tag, title: "\(entry.name) \(entry.version)")
        let asset = try await uploadAsset(owner: owner, repo: repo, token: token,
                                          releaseID: release, ipa: ipa,
                                          name: safeFileName(entry.name) + ".ipa")

        let manifest = LocalServer.manifest(ipaURL: asset.absoluteString,
                                            bundleID: entry.bundleID,
                                            version: entry.version,
                                            title: entry.name)
        let id = UUID().uuidString.lowercased()
        let path = "docs/manifests/\(id).xml"
        try await putFile(owner: owner, repo: repo, branch: branch, token: token,
                          path: path, data: Data(manifest.utf8),
                          message: "Add manifest for \(entry.name) \(entry.version)")

        let url = pages.appendingPathComponent("manifests/\(id).xml")
        try await waitUntilPublished(url)
        return url
    }

    /// Quick diagnostic used by the settings screen.
    static func test() async -> String {
        guard GitHubHostingConfig.isConfigured else { return "Enter a token first (and check owner/repository)." }
        do {
            let repo = try await getRepo(owner: GitHubHostingConfig.owner,
                                         repo: GitHubHostingConfig.repo,
                                         token: GitHubHostingConfig.token)
            let defaultBranch = repo["default_branch"] as? String ?? "?"
            let pages = try await pagesInfo(owner: GitHubHostingConfig.owner,
                                            repo: GitHubHostingConfig.repo,
                                            token: GitHubHostingConfig.token)
            if let pages {
                let url = (pages["html_url"] as? String) ?? GitHubHostingConfig.pagesBase?.absoluteString ?? "?"
                let status = (pages["status"] as? String) ?? "?"
                return "OK — repository found (default branch: \(defaultBranch)). Pages: \(status) — \(url)"
            }
            return "Repository found (default branch: \(defaultBranch)), but Pages is not enabled yet. It will be enabled automatically on the first install."
        } catch {
            return "Failed: \(error.localizedDescription)"
        }
    }

    // MARK: Repository

    private static func getRepo(owner: String, repo: String, token: String) async throws -> [String: Any] {
        let (data, response) = try await api(token: token,
                                             path: "/repos/\(owner)/\(repo)")
        guard response.statusCode == 200 else {
            throw APIError(message: apiMessage(data, response, fallback: "Repository \(owner)/\(repo) was not found."))
        }
        return jsonObject(data) ?? [:]
    }

    private static func ensureRepository(owner: String, repo: String, token: String) async throws {
        let (_, response) = try await api(token: token, path: "/repos/\(owner)/\(repo)")
        if response.statusCode == 200 { return }
        guard response.statusCode == 404 else {
            throw APIError(message: "Cannot access \(owner)/\(repo) (HTTP \(response.statusCode)).")
        }

        // Create it under the authenticated account. Works only when owner is
        // the token's own account; otherwise the repository must exist already.
        let body: [String: Any] = ["name": repo, "private": false, "auto_init": true,
                                   "description": "TrollSign IPA hosting"]
        let (data, created) = try await api(token: token, path: "/user/repos", method: "POST", json: body)
        guard created.statusCode == 201 || created.statusCode == 422 else {
            throw APIError(message: apiMessage(data, created, fallback: "Cannot create \(owner)/\(repo)."))
        }
    }

    // MARK: Pages

    private static func pagesInfo(owner: String, repo: String, token: String) async throws -> [String: Any]? {
        let (data, response) = try await api(token: token, path: "/repos/\(owner)/\(repo)/pages")
        if response.statusCode == 404 { return nil }
        guard response.statusCode == 200 else {
            throw APIError(message: apiMessage(data, response, fallback: "Cannot read Pages settings (HTTP \(response.statusCode))."))
        }
        return jsonObject(data)
    }

    /// Returns the base URL that Pages actually serves.
    private static func ensurePages(owner: String, repo: String, branch: String, token: String) async throws -> URL {
        if let info = try await pagesInfo(owner: owner, repo: repo, token: token),
           let html = info["html_url"] as? String, let url = URL(string: html) {
            return url.hasDirectoryPath ? url : url.appendingPathComponent("")
        }

        let body: [String: Any] = [
            "build_type": "legacy",
            "source": ["branch": branch, "path": "/docs"]
        ]
        let (data, response) = try await api(token: token,
                                             path: "/repos/\(owner)/\(repo)/pages",
                                             method: "POST", json: body)
        if response.statusCode == 201 || response.statusCode == 204 || response.statusCode == 409 {
            if let info = try await pagesInfo(owner: owner, repo: repo, token: token),
               let html = info["html_url"] as? String, let url = URL(string: html) {
                return url
            }
            if let base = GitHubHostingConfig.pagesBase { return base }
        }
        throw APIError(message: apiMessage(data, response, fallback: "Cannot enable GitHub Pages (HTTP \(response.statusCode)). Enable it manually: Settings → Pages → Deploy from branch → \(branch) / docs."))
    }

    // MARK: Releases

    private static func createRelease(owner: String, repo: String, token: String,
                                      tag: String, title: String) async throws -> Int {
        let body: [String: Any] = [
            "tag_name": tag,
            "name": title,
            "body": "Signed with TrollSign.",
            "draft": false,
            "prerelease": false
        ]
        let (data, response) = try await api(token: token,
                                             path: "/repos/\(owner)/\(repo)/releases",
                                             method: "POST", json: body)
        guard response.statusCode == 201,
              let obj = jsonObject(data),
              let id = obj["id"] as? Int else {
            throw APIError(message: apiMessage(data, response, fallback: "Cannot create a GitHub release."))
        }
        return id
    }

    private static func uploadAsset(owner: String, repo: String, token: String,
                                    releaseID: Int, ipa: URL, name: String) async throws -> URL {
        var comps = URLComponents(string: "https://uploads.github.com/repos/\(owner)/\(repo)/releases/\(releaseID)/assets")!
        comps.queryItems = [URLQueryItem(name: "name", value: name)]
        var request = URLRequest(url: comps.url!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.upload(for: request, fromFile: ipa)
        guard let http = response as? HTTPURLResponse, http.statusCode == 201,
              let obj = jsonObject(data),
              let urlString = obj["browser_download_url"] as? String,
              let url = URL(string: urlString) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw APIError(message: apiMessage(data, response, fallback: "IPA upload failed (HTTP \(code))."))
        }
        return url
    }

    // MARK: Contents

    private static func putFile(owner: String, repo: String, branch: String, token: String,
                                path: String, data: Data, message: String) async throws {
        let body: [String: Any] = [
            "message": message,
            "content": data.base64EncodedString(),
            "branch": branch
        ]
        let encodedPath = path.split(separator: "/").map {
            String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0)
        }.joined(separator: "/")
        let (responseData, response) = try await api(token: token,
                                                     path: "/repos/\(owner)/\(repo)/contents/\(encodedPath)",
                                                     method: "PUT", json: body)
        guard response.statusCode == 200 || response.statusCode == 201 else {
            throw APIError(message: apiMessage(responseData, response, fallback: "Cannot write \(path) to GitHub."))
        }
    }

    // MARK: Helpers

    private static func jsonObject(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func apiMessage(_ data: Data, _ response: URLResponse, fallback: String) -> String {
        if let obj = jsonObject(data),
           let message = obj["message"] as? String {
            return "\(message) (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0))"
        }
        return "\(fallback) (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0))"
    }

    private static func api(token: String, path: String, method: String = "GET",
                            json: [String: Any]? = nil) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: "https://api.github.com" + path) else {
            throw APIError(message: "Bad GitHub API URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("TrollSign", forHTTPHeaderField: "User-Agent")
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError(message: "No HTTP response from GitHub.")
        }
        return (data, http)
    }

    private static func waitUntilPublished(_ url: URL) async throws {
        // Pages usually rebuilds in 30–90 seconds. Keep trying so the system
        // install dialog does not open against a 404 manifest.
        for attempt in 0..<40 {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            if let (data, response) = try? await URLSession.shared.data(for: request),
               let http = response as? HTTPURLResponse, http.statusCode == 200,
               let text = String(data: data, encoding: .utf8), text.contains("<plist") {
                return
            }
            if attempt < 39 {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
        throw APIError(message: "The manifest was uploaded, but GitHub Pages has not published it yet. Open the GitHub repository → Actions and wait for the “pages build and deployment” job, then try Reinstall.")
    }

    private static func safeFileName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let out = name.unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }.joined()
            .trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        return out.isEmpty ? "app" : out
    }
}
