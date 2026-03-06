import Foundation
import Security

/// Сохранение и загрузка параметров подключения и папки сохранения.
final class SettingsStore: ObservableObject {
    private let defaults = UserDefaults.standard
    private let keyServer = "webdav.serverURL"
    private let keyLogin = "webdav.login"
    private let keySaveDirectory = "webdav.saveDirectory"
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

    init() {
        self.serverURL = defaults.string(forKey: keyServer) ?? "https://"
        self.login = defaults.string(forKey: keyLogin) ?? ""
        self.password = Self.loadPasswordFromKeychain(service: keychainService) ?? ""
        if let path = defaults.string(forKey: keySaveDirectory) {
            self.saveDirectory = URL(fileURLWithPath: path)
        } else {
            self.saveDirectory = nil
        }
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
