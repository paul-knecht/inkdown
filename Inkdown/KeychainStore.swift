import Foundation
import Security

// Saves the Anthropic API key in the macOS Keychain, the system's
// encrypted store for passwords. The key is never written to a file.
struct KeychainStore {

    // Together these two names identify our entry in the Keychain.
    let service: String
    let account: String

    init(service: String = "local.inkdown", account: String = "anthropic-api-key") {
        self.service = service
        self.account = account
    }

    // The description of our entry that every Keychain call needs.
    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    // Stores the key, replacing any older one. Returns true if it worked.
    @discardableResult
    func save(_ key: String) -> Bool {
        delete()
        var entry = query
        entry[kSecValueData as String] = Data(key.utf8)
        return SecItemAdd(entry as CFDictionary, nil) == errSecSuccess
    }

    // Returns the stored key, or nil if there is none.
    func load() -> String? {
        var search = query
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        guard SecItemCopyMatching(search as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    // Removes the stored key. Does nothing if there is none.
    func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
