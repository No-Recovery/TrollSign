import Foundation
import Network
import Security

// MARK: - Конфиг сервера установки

/// Для itms-services нужен HTTPS с доверенным сертификатом. Схема как в ESign:
/// домен, который резолвится в 127.0.0.1, + настоящий сертификат на этот домен (.p12).
/// Приложение поднимает HTTPS-сервер на loopback и отдаёт manifest.plist и IPA.
enum ServerConfig {
    static var dir: URL {
        let b = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Server", isDirectory: true)
        try? FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        return b
    }
    static var p12URL: URL { dir.appendingPathComponent("server.p12") }
    /// Адрес по умолчанию — localhost.direct (можно сменить в Certs -> Installation Server).
    static var host: String {
        let h = (UserDefaults.standard.string(forKey: "serverHost") ?? "").trimmingCharacters(in: .whitespaces)
        return h.isEmpty ? "localhost.direct" : h
    }
    /// Серверный .p12, вшитый в приложение: положи server.p12 в проект (Copy Bundle Resources).
    /// Пароль по умолчанию для набора localhost.direct — "localhost"; поменяй, если у тебя другой.
    static let bundledPassword = "localhost"
    static var bundledURL: URL? { Bundle.main.url(forResource: "server", withExtension: "p12") }
    static var port: UInt16 {
        let p = UserDefaults.standard.integer(forKey: "serverPort")
        return p > 0 && p < 65536 ? UInt16(p) : 8443
    }
    static var hasImportedCert: Bool { FileManager.default.fileExists(atPath: p12URL.path) }
    static var hasCert: Bool { hasImportedCert || bundledURL != nil }

    static func importP12(from url: URL, password: String) throws {
        _ = try load(data: Data(contentsOf: url), password: password)   // проверка пароля
        try? FileManager.default.removeItem(at: p12URL)
        try FileManager.default.copyItem(at: url, to: p12URL)
        Keychain.set(password, for: "server.p12")
    }

    static func identity() throws -> (SecIdentity, [SecCertificate]) {
        if hasImportedCert {
            return try load(data: Data(contentsOf: p12URL), password: Keychain.get("server.p12") ?? "")
        }
        if let b = bundledURL { return try load(data: Data(contentsOf: b), password: bundledPassword) }
        throw AppError("No server certificate. Put server.p12 into the project (see README) or import it in Certs > Installation Server.")
    }

    private static func load(data: Data, password: String) throws -> (SecIdentity, [SecCertificate]) {
        var items: CFArray?
        let st = SecPKCS12Import(data as CFData, [kSecImportExportPassphrase as String: password] as CFDictionary, &items)
        guard st == errSecSuccess, let arr = items as? [[String: Any]], let first = arr.first,
              let idRef = first[kSecImportItemIdentity as String] else {
            throw AppError(st == errSecAuthFailed ? "Wrong password for the server .p12" : "Cannot read the server .p12 (code \(st))")
        }
        let chain = (first[kSecImportItemCertChain as String] as? [SecCertificate]) ?? []
        return (idRef as! SecIdentity, chain)
    }
}

// MARK: - HTTPS-сервер на loopback

final class LocalServer {
    static let shared = LocalServer()

    struct Item { let ipa: URL; let bundleID: String; let version: String; let title: String }

    private var listener: NWListener?
    private var runningPort: UInt16 = 0
    private var items: [String: Item] = [:]
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "trollstorelite.server")

    func register(id: String, item: Item) { lock.lock(); items[id] = item; lock.unlock() }
    private func item(_ id: String) -> Item? { lock.lock(); defer { lock.unlock() }; return items[id] }

    func start() async throws {
        let port = ServerConfig.port
        if listener != nil, runningPort == port { return }
        stop()

        let (identity, chain) = try ServerConfig.identity()
        let tls = NWProtocolTLS.Options()
        let secID: sec_identity_t?
        if chain.count > 1 {
            secID = sec_identity_create_with_certificates(identity, Array(chain.dropFirst()) as CFArray)
        } else {
            secID = sec_identity_create(identity)
        }
        guard let secID else { throw AppError("Cannot use the server certificate") }
        sec_protocol_options_set_local_identity(tls.securityProtocolOptions, secID)

        let params = NWParameters(tls: tls)
        params.requiredInterfaceType = .loopback
        guard let p = NWEndpoint.Port(rawValue: port) else { throw AppError("Bad port") }
        let l = try NWListener(using: params, on: p)
        l.newConnectionHandler = { [weak self] c in self?.handle(c) }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var resumed = false
            l.stateUpdateHandler = { state in
                guard !resumed else { return }
                switch state {
                case .ready: resumed = true; cont.resume()
                case .failed(let e): resumed = true; cont.resume(throwing: e)
                case .cancelled: resumed = true; cont.resume(throwing: AppError("Server cancelled"))
                default: break
                }
            }
            l.start(queue: queue)
        }
        listener = l
        runningPort = port
    }

    func stop() { listener?.cancel(); listener = nil; runningPort = 0 }

    /// Проверка: домен резолвится в 127.0.0.1 и сертификат валиден для него.
    func selfTest() async -> String {
        do {
            try await start()
            guard let url = URL(string: "https://\(ServerConfig.host):\(ServerConfig.port)/ping") else { return "Bad host" }
            let (d, _) = try await URLSession.shared.data(from: url)
            return String(data: d, encoding: .utf8) == "ok" ? "Server OK" : "Unexpected answer"
        } catch { return "Failed: \(error.localizedDescription)" }
    }

    // MARK: HTTP

    private func handle(_ c: NWConnection) {
        c.start(queue: queue)
        receive(c, Data())
    }

    private func receive(_ c: NWConnection, _ buf: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, done, err in
            guard let self else { return }
            var b = buf; if let data { b.append(data) }
            if b.range(of: Data("\r\n\r\n".utf8)) != nil { self.respond(c, b) }
            else if done || err != nil || b.count > 65536 { c.cancel() }
            else { self.receive(c, b) }
        }
    }

    private func send(_ c: NWConnection, status: String, type: String, body: Data, head: Bool = false) {
        let h = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var out = Data(h.utf8); if !head { out.append(body) }
        c.send(content: out, completion: .contentProcessed { _ in c.cancel() })
    }

    private func respond(_ c: NWConnection, _ req: Data) {
        let text = String(decoding: req, as: UTF8.self)
        let first = text.components(separatedBy: "\r\n").first ?? ""
        let parts = first.split(separator: " ")
        guard parts.count >= 2 else { return send(c, status: "400 Bad Request", type: "text/plain", body: Data()) }
        let head = parts[0] == "HEAD"
        let path = String(parts[1]).components(separatedBy: "?")[0]

        if path == "/ping" { return send(c, status: "200 OK", type: "text/plain", body: Data("ok".utf8), head: head) }

        let name = String(path.dropFirst())
        if name.hasSuffix(".plist"), let it = item(String(name.dropLast(6))) {
            let url = "https://\(ServerConfig.host):\(ServerConfig.port)/\(name.dropLast(6)).ipa"
            let xml = Self.manifest(ipaURL: url, bundleID: it.bundleID, version: it.version, title: it.title)
            return send(c, status: "200 OK", type: "text/xml", body: Data(xml.utf8), head: head)
        }
        if name.hasSuffix(".ipa"), let it = item(String(name.dropLast(4))),
           let size = (try? FileManager.default.attributesOfItem(atPath: it.ipa.path)[.size]) as? UInt64,
           let fh = try? FileHandle(forReadingFrom: it.ipa) {
            let h = "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: \(size)\r\nConnection: close\r\n\r\n"
            if head { fh.closeFile(); return c.send(content: Data(h.utf8), completion: .contentProcessed { _ in c.cancel() }) }
            c.send(content: Data(h.utf8), completion: .contentProcessed { [weak self] e in
                if e != nil { fh.closeFile(); c.cancel() } else { self?.stream(c, fh, size) }
            })
            return
        }
        send(c, status: "404 Not Found", type: "text/plain", body: Data("not found".utf8), head: head)
    }

    private func stream(_ c: NWConnection, _ fh: FileHandle, _ remaining: UInt64) {
        let chunk = fh.readData(ofLength: Int(min(1 << 20, remaining)))
        if chunk.isEmpty { fh.closeFile(); c.cancel(); return }
        let left = remaining - UInt64(chunk.count)
        c.send(content: chunk, completion: .contentProcessed { [weak self] e in
            if e != nil || left == 0 { fh.closeFile(); c.cancel() } else { self?.stream(c, fh, left) }
        })
    }

    static func manifest(ipaURL: String, bundleID: String, version: String, title: String) -> String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>items</key><array><dict>
        <key>assets</key><array><dict><key>kind</key><string>software-package</string>
        <key>url</key><string>\(esc(ipaURL))</string></dict></array>
        <key>metadata</key><dict>
        <key>bundle-identifier</key><string>\(esc(bundleID))</string>
        <key>bundle-version</key><string>\(esc(version))</string>
        <key>kind</key><string>software</string>
        <key>title</key><string>\(esc(title))</string></dict>
        </dict></array></dict></plist>
        """
    }
}
