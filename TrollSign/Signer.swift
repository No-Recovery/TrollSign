import Foundation
import ZIPFoundation
import ZSign

/// Signs an IPA with zsign.
///
/// The `zsign-ios` package can only sign an *extracted* `.app` bundle, so the
/// IPA is unpacked into a temporary directory, signed in place and packed back.
enum Signer {
    enum SignError: LocalizedError {
        case badIPA(String)
        case zsign(Int32)

        var errorDescription: String? {
            switch self {
            case .badIPA(let detail):
                return "Cannot unpack the IPA: \(detail)"
            case .zsign(let code):
                return "zsign failed (code \(code)). Check that the .p12 password is correct and the .mobileprovision matches the certificate."
            }
        }
    }

    static func sign(ipa: URL, p12: URL, password: String, profile: URL, output: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let root = fm.temporaryDirectory
                .appendingPathComponent("TrollSign-\(UUID().uuidString)", isDirectory: true)
            defer { try? fm.removeItem(at: root) }

            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            try unzip(ipa, to: root)

            let payload = root.appendingPathComponent("Payload", isDirectory: true)
            let apps = (try? fm.contentsOfDirectory(at: payload, includingPropertiesForKeys: nil)) ?? []
            guard let app = apps.first(where: { $0.pathExtension.lowercased() == "app" }) else {
                throw SignError.badIPA("Payload/*.app was not found")
            }

            // certFile and pKeyFile are the same .p12: zsign extracts both the
            // certificate and the private key from it.
            let code = zsign(app.path, p12.path, p12.path, profile.path, password, nil, nil)
            guard code == 0 else { throw SignError.zsign(code) }

            try? fm.removeItem(at: output)
            try zip(payload, to: output)
        }.value
    }

    // MARK: - ZIP

    private static func unzip(_ ipa: URL, to root: URL) throws {
        let fm = FileManager.default
        let archive: Archive
        do {
            archive = try Archive(url: ipa, accessMode: .read)
        } catch {
            throw SignError.badIPA(error.localizedDescription)
        }

        for entry in archive {
            // Reject path traversal ("../../...").
            let parts = entry.path.split(separator: "/", omittingEmptySubsequences: true)
            guard !parts.contains("..") else { continue }

            let dest = root.appendingPathComponent(entry.path)
            if entry.type == .directory {
                try fm.createDirectory(at: dest, withIntermediateDirectories: true)
                continue
            }
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            do {
                _ = try archive.extract(entry, to: dest)
            } catch {
                throw SignError.badIPA("\(entry.path): \(error.localizedDescription)")
            }
        }
    }

    private static func zip(_ payload: URL, to output: URL) throws {
        let fm = FileManager.default
        let archive = try Archive(url: output, accessMode: .create)

        // Root "Payload/" directory entry.
        try archive.addEntry(with: "Payload", fileURL: payload, compressionMethod: .none)

        guard let enumerator = fm.enumerator(at: payload,
                                             includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                                             options: []) else {
            throw SignError.badIPA("Cannot enumerate Payload")
        }
        for case let url as URL in enumerator {
            let relative = url.path.replacingOccurrences(of: payload.deletingLastPathComponent().path + "/", with: "")
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            try archive.addEntry(with: relative, fileURL: url,
                                 compressionMethod: isDirectory ? .none : .deflate)
        }
    }
}
