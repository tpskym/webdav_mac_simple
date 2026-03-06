import Foundation
import Security

/// Сохранение и загрузка параметров подключения и папки сохранения.
final class SettingsStore: ObservableObject {
    private let defaults = UserDefaults.standard
    private let keyServer = "webdav.serverURL"
    private let keyLogin = "webdav.login"
    private let keySaveDirectory = "webdav.saveDirectory"
    private let keyLastOpenPath = "webdav.lastOpenPath"
    private let keyLastOpenPathServer = "webdav.lastOpenPathServerURL"
    private let keychainService = "com.webdav.client"

    @Published var serverURL: String {
        didSet { defaults.set(serverURL, forKey: keyServer) }
    }

    @Published var login: String {
        didSet { defaults.set(login, forKey: keyLogin) }
    }

    @Published var password: String {
        didSet { savePasswordToKeychain(password) }
    }

    @Published var saveDirectory: URL? {
        didSet {
            if let url = saveDirectory {
                defaults.set(url.path, forKey: keySaveDirectory)
            } else {
                defaults.removeObject(forKey: keySaveDirectory)
            }
        }
    }

    /// Последняя открытая папка на сервере (путь без ведущего слэша, например "docs/2024").
    @Published var lastOpenPath: String? {
        didSet {
            if let v = lastOpenPath, !v.isEmpty {
                defaults.set(v, forKey: keyLastOpenPath)
            } else {
                defaults.removeObject(forKey: keyLastOpenPath)
            }
        }
    }

    /// URL сервера, для которого сохранён lastOpenPath (для восстановления только при том же сервере).
    @Published var lastOpenPathServerURL: String? {
        didSet {
            if let v = lastOpenPathServerURL {
                defaults.set(v, forKey: keyLastOpenPathServer)
            } else {
                defaults.removeObject(forKey: keyLastOpenPathServer)
            }
        }
    }

    init() {
        self.serverURL = defaults.string(forKey: keyServer) ?? "https://"
        self.login = defaults.string(forKey: keyLogin) ?? ""
        self.password = Self.loadPasswordFromKeychain(service: keychainService) ?? ""
        if let path = defaults.string(forKey: keySaveDirectory) {
            self.saveDirectory = URL(fileURLWithPath: path)
        } else {
            self.saveDirectory = nil
        }
        self.lastOpenPath = defaults.string(forKey: keyLastOpenPath)
        self.lastOpenPathServerURL = defaults.string(forKey: keyLastOpenPathServer)
    }

    private func savePasswordToKeychain(_ value: String) {
        let data = value.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "password"
        ]
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData as String] = data
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private static func loadPasswordFromKeychain(service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "password",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }
}
