import Foundation

/// Сервис для работы с WebDAV по HTTPS: список каталога и скачивание файлов.
final class WebDAVService: NSObject {
    private var session: URLSession!
    private let credentials: WebDAVCredentials

    init(credentials: WebDAVCredentials) {
        self.credentials = credentials
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.urlCredentialStorage = nil
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    /// Запрашивает список ресурсов по указанному пути (относительно baseURL).
    func list(path: String = "/") async throws -> [WebDAVResource] {
        var url = credentials.baseURL
        let normalizedPath = normalizeRelativePath(path)
        if !normalizedPath.isEmpty {
            for component in normalizedPath.split(separator: "/").map(String.init) {
                url = url.appendingPathComponent(component)
            }
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        request.setValue(credentials.authHeaderValue(), forHTTPHeaderField: "Authorization")

        let propfindBody =
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" +
            "<d:propfind xmlns:d=\"DAV:\">" +
            "<d:prop>" +
            "<d:displayname/><d:getcontentlength/><d:getlastmodified/><d:resourcetype/>" +
            "</d:prop>" +
            "</d:propfind>"
        request.httpBody = propfindBody.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WebDAVError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw WebDAVError.httpStatus(http.statusCode)
        }

        return try parsePropfindResponse(data: data, baseURL: credentials.baseURL)
    }

    /// Скачивает файл по href и сохраняет в локальную папку.
    func download(href: String, to localURL: URL) async throws {
        let url = resolveURL(href: href)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(credentials.authHeaderValue(), forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw WebDAVError.httpStatus(code)
        }

        try data.write(to: localURL)
    }

    /// Загружает файл на сервер (PUT). remotePath — путь относительно baseURL, например "folder/file.txt".
    func upload(localFile: URL, remotePath: String) async throws {
        let data = try Data(contentsOf: localFile)
        var url = credentials.baseURL
        let path = normalizeRelativePath(remotePath)
        if !path.isEmpty {
            for component in path.split(separator: "/").map(String.init) {
                url = url.appendingPathComponent(component)
            }
        } else {
            url = url.appendingPathComponent(localFile.lastPathComponent)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(credentials.authHeaderValue(), forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw WebDAVError.httpStatus(code)
        }
    }

    private func resolveURL(href: String) -> URL {
        if let absolute = URL(string: href), absolute.scheme != nil {
            return absolute
        }
        let base = credentials.baseURL
        if href.hasPrefix("/") {
            var comp = URLComponents(url: base, resolvingAgainstBaseURL: false)!
            comp.percentEncodedPath = href
            return comp.url!
        }
        if let relative = URL(string: href, relativeTo: base)?.absoluteURL {
            return relative
        }
        return base.appendingPathComponent(normalizeRelativePath(href))
    }

    /// Нормализует относительный путь и устраняет двойное percent-encoding.
    private func normalizeRelativePath(_ value: String) -> String {
        value
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .split(separator: "/")
            .map(String.init)
            .map { $0.removingPercentEncoding ?? $0 }
            .joined(separator: "/")
    }

    // MARK: - PROPFIND XML parsing

    private func parsePropfindResponse(data: Data, baseURL: URL) throws -> [WebDAVResource] {
        let parser = WebDAVPropfindParser(baseURL: baseURL)
        try parser.parse(data: data)
        return parser.resources
    }
}

// MARK: - URLSessionTaskDelegate (auth challenge + self-signed cert)

extension WebDAVService: URLSessionTaskDelegate {

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        switch challenge.protectionSpace.authenticationMethod {

        // Обрабатываем Basic / Digest / NTLM — передаём логин и пароль
        case NSURLAuthenticationMethodHTTPBasic,
             NSURLAuthenticationMethodHTTPDigest,
             NSURLAuthenticationMethodNTLM:
            if challenge.previousFailureCount == 0 {
                let cred = URLCredential(
                    user: credentials.login,
                    password: credentials.password,
                    persistence: .forSession
                )
                completionHandler(.useCredential, cred)
            } else {
                // Уже пробовали — явно неверные данные
                completionHandler(.cancelAuthenticationChallenge, nil)
            }

        // Самоподписанный / недоверенный сертификат — доверяем серверу
        case NSURLAuthenticationMethodServerTrust:
            if let trust = challenge.protectionSpace.serverTrust {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                completionHandler(.performDefaultHandling, nil)
            }

        default:
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

// MARK: - Errors

enum WebDAVError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case xmlParse(String?)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Некорректный ответ сервера"
        case .httpStatus(let code):
            let hint: String
            switch code {
            case 401: hint = "Неверные логин или пароль (HTTP 401)"
            case 403: hint = "Доступ запрещён (HTTP 403)"
            case 404: hint = "Путь не найден (HTTP 404)"
            case 405: hint = "Метод не поддерживается сервером (HTTP 405)"
            case 500...599: hint = "Ошибка сервера (HTTP \(code))"
            default: hint = "HTTP \(code)"
            }
            return hint
        case .xmlParse(let msg):
            return "Ошибка разбора XML: \(msg ?? "неизвестно")"
        }
    }
}

// MARK: - PROPFIND XML Parser

private final class WebDAVPropfindParser: NSObject, XMLParserDelegate {
    var resources: [WebDAVResource] = []
    private let baseURL: URL
    private var currentHref: String?
    private var currentDisplayName: String?
    private var currentIsCollection: Bool = false
    private var currentContentLength: Int64?
    private var currentLastModified: Date?
    private var inResponse: Bool = false
    private var inProp: Bool = false
    private let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    func parse(data: Data) throws {
        resources = []
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw WebDAVError.xmlParse(parser.parserError?.localizedDescription)
        }
    }

    /// Локальное имя тега без префикса пространства имён (d:response → response).
    private static func localName(_ elementName: String) -> String {
        if let i = elementName.firstIndex(of: ":") {
            return String(elementName[elementName.index(after: i)...])
        }
        return elementName
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let name = Self.localName(elementName).lowercased()
        switch name {
        case "response":
            inResponse = true
            currentHref = nil
            currentDisplayName = nil
            currentIsCollection = false
            currentContentLength = nil
            currentLastModified = nil
        case "href":
            currentElement = .href
        case "prop":
            inProp = true
        case "displayname":
            if inProp { currentElement = .displayname }
        case "getcontentlength":
            if inProp { currentElement = .contentlength }
        case "getlastmodified":
            if inProp { currentElement = .lastmodified }
        case "resourcetype":
            currentElement = .resourcetype
        case "collection":
            if currentElement == .resourcetype { currentIsCollection = true }
        default:
            break
        }
    }

    private enum Element { case href, displayname, contentlength, lastmodified, resourcetype }
    private var currentElement: Element?
    private var currentCharacters: String = ""

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentCharacters += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = Self.localName(elementName).lowercased()
        switch name {
        case "response":
            if let href = currentHref, !href.isEmpty {
                let name = currentDisplayName ?? (href.split(separator: "/").last.map(String.init) ?? href)
                let id = (baseURL.absoluteString + href).addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? href
                resources.append(WebDAVResource(
                    id: id,
                    href: href,
                    displayName: name,
                    isCollection: currentIsCollection,
                    contentLength: currentContentLength,
                    lastModified: currentLastModified
                ))
            }
            inResponse = false
        case "prop":
            inProp = false
        case "href":
            currentHref = currentCharacters.trimmingCharacters(in: .whitespacesAndNewlines)
            currentElement = nil
        case "displayname":
            if currentElement == .displayname {
                currentDisplayName = currentCharacters.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            currentElement = nil
        case "getcontentlength":
            if currentElement == .contentlength, let n = Int64(currentCharacters.trimmingCharacters(in: .whitespacesAndNewlines)) {
                currentContentLength = n
            }
            currentElement = nil
        case "getlastmodified":
            if currentElement == .lastmodified {
                let raw = currentCharacters.trimmingCharacters(in: .whitespacesAndNewlines)
                currentLastModified = ISO8601DateFormatter().date(from: raw)
                    ?? HTTPDateFormatter().date(from: raw)
            }
            currentElement = nil
        case "resourcetype", "collection":
            currentElement = nil
        default:
            break
        }
        currentCharacters = ""
    }
}

private final class HTTPDateFormatter {
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        f.timeZone = TimeZone(identifier: "GMT")
        return f
    }()

    func date(from string: String) -> Date? {
        formatter.date(from: string)
    }
}
