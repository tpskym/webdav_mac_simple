import Foundation

/// Элемент списка WebDAV (файл или коллекция/папка).
struct WebDAVResource: Identifiable {
    let id: String
    let href: String
    let displayName: String
    let isCollection: Bool
    let contentLength: Int64?
    let lastModified: Date?

    var isDirectory: Bool { isCollection }
}

/// Учётные данные и URL сервера WebDAV.
struct WebDAVCredentials {
    let baseURL: URL
    let login: String
    let password: String

    func authHeaderValue() -> String {
        let raw = "\(login):\(password)"
        let data = raw.data(using: .utf8) ?? Data()
        return "Basic \(data.base64EncodedString())"
    }
}
