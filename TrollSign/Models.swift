import Foundation

struct IPAEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var bundleID: String
    var version: String
    var fileName: String
    var iconFile: String?
    var size: Int64 = 0
    var signedFileName: String?
    var addedAt = Date()
}

struct CertEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var teamName: String
    var expiration: Date?
    var p12File: String
    var provFile: String
    var isExpired: Bool { (expiration ?? .distantFuture) < Date() }
}

enum PendingInstall: Identifiable {
    case local(URL), remote(URL)
    var id: String {
        switch self { case .local(let u): return "l" + u.absoluteString
                      case .remote(let u): return "r" + u.absoluteString }
    }
}

struct AppError: LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}
