import Foundation

/// The OpenRouter API key, kept in Corrector's preferences. The Keychain asked for the login password
/// after every rebuild, because each ad-hoc signed build counts as a different app.
enum APIKeyStore {
    private static let defaultsKey = "openRouterAPIKey"

    static func read() -> String? {
        guard let key = UserDefaults.standard.string(forKey: defaultsKey)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty else { return nil }
        return key
    }

    static func save(_ key: String) {
        UserDefaults.standard.set(key, forKey: defaultsKey)
    }

    static func delete() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}
