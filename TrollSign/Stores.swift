import Foundation
import ZIPFoundation

private func dir(_ base: FileManager.SearchPathDirectory, _ sub: String) -> URL {
    let b = FileManager.default.urls(for: base, in: .userDomainMask)[0]
    let u = b.appendingPathComponent(sub, isDirectory: true)
    try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

// MARK: - IPA

@MainActor
final class AppStore: ObservableObject {
    @Published var apps: [IPAEntry] = [] { didSet { save() } }
    @Published var busy = false
    @Published var statusText = ""
    @Published var pending: PendingInstall?
    @Published var errorText: String?
    weak var certs: CertStore?

    let ipaDir = dir(.documentDirectory, "IPAs")
    let signedDir = dir(.documentDirectory, "Signed")
    let iconDir = dir(.applicationSupportDirectory, "Icons")
    private var indexURL: URL { dir(.applicationSupportDirectory, "Index").appendingPathComponent("apps.json") }

    init() {
        if let d = try? Data(contentsOf: indexURL),
           let a = try? JSONDecoder().decode([IPAEntry].self, from: d) { apps = a }
    }
    private func save() { try? JSONEncoder().encode(apps).write(to: indexURL) }

    // Режим подтверждения: 0 = Always, 1 = Only on Remote URL Installs, 2 = Never
    func request(_ p: PendingInstall) {
        let mode = UserDefaults.standard.integer(forKey: "confirmMode")
        var needConfirm = mode == 0
        if case .remote = p, mode == 1 { needConfirm = true }
        if needConfirm { pending = p } else { run(p) }
    }

    func run(_ p: PendingInstall) {
        pending = nil
        Task {
            do {
                let entry: IPAEntry
                switch p {
                case .local(let u): entry = try importIPA(from: u)
                case .remote(let u): entry = try await importIPA(fromRemote: u)
                }
                await installEntry(entry)
            } catch { errorText = error.localizedDescription }
        }
    }

    /// Подпись выбранным сертификатом -> локальный HTTPS-сервер -> itms-services.
    func installEntry(_ e: IPAEntry) async {
        busy = true
        defer { busy = false; statusText = "" }
        do {
            guard let certs, let c = certs.selected else {
                throw AppError("No certificate. Open Settings, long-press the version, then Settings → Advanced → Certificates and add one.")
            }
            if c.isExpired { throw AppError("The selected provisioning profile has expired.") }

            statusText = "Signing…"
            let out = signedDir.appendingPathComponent(UUID().uuidString + ".ipa")
            try await Signer.sign(ipa: ipaURL(e), p12: certs.p12URL(c),
                                  password: Keychain.get(c.id.uuidString) ?? "",
                                  profile: certs.provURL(c), output: out)
            var entry = e
            if let i = apps.firstIndex(where: { $0.id == e.id }) {
                if let old = apps[i].signedFileName { try? FileManager.default.removeItem(at: signedURL(old)) }
                apps[i].signedFileName = out.lastPathComponent
                entry = apps[i]
            }
            statusText = "Installing…"
            try await Installer.install(signedIPA: out, entry: entry)
        } catch { errorText = error.localizedDescription }
    }

    @discardableResult
    func importIPA(from url: URL) throws -> IPAEntry {
        let ext = url.pathExtension.lowercased()
        guard ext == "ipa" || ext == "tipa" else { throw AppError("Not an .ipa file: \(url.lastPathComponent)") }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let dest = ipaDir.appendingPathComponent(UUID().uuidString + ".ipa")
        try FileManager.default.copyItem(at: url, to: dest)
        return try register(dest)
    }

    func importIPA(fromRemote remote: URL) async throws -> IPAEntry {
        busy = true; statusText = "Downloading…"
        defer { busy = false; statusText = "" }
        let (tmp, resp) = try await URLSession.shared.download(from: remote)
        if let h = resp as? HTTPURLResponse, !(200..<300).contains(h.statusCode) {
            throw AppError("Server returned \(h.statusCode)")
        }
        let dest = ipaDir.appendingPathComponent(UUID().uuidString + ".ipa")
        try FileManager.default.moveItem(at: tmp, to: dest)
        return try register(dest)
    }

    private func register(_ file: URL) throws -> IPAEntry {
        do {
            let info = try Self.readInfo(ipa: file)
            var entry = IPAEntry(name: info.name, bundleID: info.bundleID, version: info.version,
                                 fileName: file.lastPathComponent)
            entry.size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64) ?? 0
            if let icon = info.icon {
                let n = entry.id.uuidString + ".png"
                try? icon.write(to: iconDir.appendingPathComponent(n))
                entry.iconFile = n
            }
            apps.insert(entry, at: 0)
            return entry
        } catch {
            try? FileManager.default.removeItem(at: file)
            throw error
        }
    }

    func delete(_ e: IPAEntry) {
        try? FileManager.default.removeItem(at: ipaDir.appendingPathComponent(e.fileName))
        if let s = e.signedFileName { try? FileManager.default.removeItem(at: signedDir.appendingPathComponent(s)) }
        if let i = e.iconFile { try? FileManager.default.removeItem(at: iconDir.appendingPathComponent(i)) }
        apps.removeAll { $0.id == e.id }
    }

    func clearSigned() {
        try? FileManager.default.removeItem(at: signedDir)
        try? FileManager.default.createDirectory(at: signedDir, withIntermediateDirectories: true)
        for i in apps.indices { apps[i].signedFileName = nil }
    }

    func ipaURL(_ e: IPAEntry) -> URL { ipaDir.appendingPathComponent(e.fileName) }
    func signedURL(_ n: String) -> URL { signedDir.appendingPathComponent(n) }
    func iconURL(_ e: IPAEntry) -> URL? { e.iconFile.map { iconDir.appendingPathComponent($0) } }

    /// Перечитать иконки из IPA ("Rebuild Icon Cache").
    func rebuildIcons() {
        for i in apps.indices {
            guard let info = try? Self.readInfo(ipa: ipaURL(apps[i])), let d = info.icon else { continue }
            let n = apps[i].id.uuidString + ".png"
            try? d.write(to: iconDir.appendingPathComponent(n))
            apps[i].iconFile = n
        }
    }

    struct Info { let name, bundleID, version: String; let icon: Data? }

    static func readInfo(ipa: URL) throws -> Info {
        let archive = try Archive(url: ipa, accessMode: .read)
        guard let plistEntry = archive.first(where: {
            let p = $0.path.split(separator: "/")
            return p.count == 3 && p[0] == "Payload" && p[1].hasSuffix(".app") && p[2] == "Info.plist"
        }) else { throw AppError("The IPA file does not appear to contain an app.") }

        var data = Data()
        _ = try archive.extract(plistEntry) { data.append($0) }
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let bid = plist["CFBundleIdentifier"] as? String
        else { throw AppError("The app's Info.plist is missing required values.") }

        let name = (plist["CFBundleDisplayName"] ?? plist["CFBundleName"]) as? String ?? bid
        let ver = plist["CFBundleShortVersionString"] as? String ?? plist["CFBundleVersion"] as? String ?? "?"

        // Иконка: самый большой PNG в корне .app с "icon" в имени
        let appDir = plistEntry.path.replacingOccurrences(of: "Info.plist", with: "")
        let icons = archive.filter {
            $0.path.hasPrefix(appDir) && $0.path.lowercased().hasSuffix(".png")
                && $0.path.dropFirst(appDir.count).lowercased().contains("icon")
                && !$0.path.dropFirst(appDir.count).contains("/")
        }.sorted { $0.uncompressedSize > $1.uncompressedSize }
        var iconData: Data?
        if let best = icons.first {
            var d = Data(); _ = try? archive.extract(best) { d.append($0) }; iconData = d
        }
        return Info(name: name, bundleID: bid, version: ver, icon: iconData)
    }
}

// MARK: - Certificates

@MainActor
final class CertStore: ObservableObject {
    @Published var certs: [CertEntry] = [] { didSet { save() } }
    @Published var selectedID: UUID?
    @Published var hiddenTabUnlocked = false

    private let root = dir(.applicationSupportDirectory, "Certs")
    private var indexURL: URL { root.appendingPathComponent("index.json") }

    init() {
        if let d = try? Data(contentsOf: indexURL),
           let c = try? JSONDecoder().decode([CertEntry].self, from: d) { certs = c }
        selectedID = certs.first?.id
    }
    private func save() { try? JSONEncoder().encode(certs).write(to: indexURL) }

    var selected: CertEntry? { certs.first { $0.id == selectedID } ?? certs.first }
    func p12URL(_ c: CertEntry) -> URL { root.appendingPathComponent(c.id.uuidString).appendingPathComponent(c.p12File) }
    func provURL(_ c: CertEntry) -> URL { root.appendingPathComponent(c.id.uuidString).appendingPathComponent(c.provFile) }

    func add(p12: URL, prov: URL, password: String) throws {
        let id = UUID()
        let d = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        do {
            try FileManager.default.copyItem(at: p12, to: d.appendingPathComponent("cert.p12"))
            try FileManager.default.copyItem(at: prov, to: d.appendingPathComponent("profile.mobileprovision"))
        } catch { try? FileManager.default.removeItem(at: d); throw error }

        let meta = Self.parseProfile(d.appendingPathComponent("profile.mobileprovision"))
        Keychain.set(password, for: id.uuidString)
        certs.append(CertEntry(id: id, name: meta.name, teamName: meta.team, expiration: meta.expiry,
                               p12File: "cert.p12", provFile: "profile.mobileprovision"))
        if selectedID == nil { selectedID = id }
    }

    func remove(_ c: CertEntry) {
        try? FileManager.default.removeItem(at: root.appendingPathComponent(c.id.uuidString))
        Keychain.delete(c.id.uuidString)
        certs.removeAll { $0.id == c.id }
        if selectedID == c.id { selectedID = certs.first?.id }
    }

    static func parseProfile(_ url: URL) -> (name: String, team: String, expiry: Date?) {
        guard let data = try? Data(contentsOf: url),
              let s = data.range(of: Data("<?xml".utf8)),
              let e = data.range(of: Data("</plist>".utf8)) else { return ("Unknown profile", "?", nil) }
        let xml = data.subdata(in: s.lowerBound..<e.upperBound)
        let p = (try? PropertyListSerialization.propertyList(from: xml, format: nil)) as? [String: Any] ?? [:]
        return (p["Name"] as? String ?? "Unknown profile", p["TeamName"] as? String ?? "?", p["ExpirationDate"] as? Date)
    }
}
