import Foundation
import Security

protocol SecureCredentialStore: Sendable {
    func credential(service: String, account: String) throws -> Data?
    func setCredential(_ credential: Data, service: String, account: String) throws
    func removeCredential(service: String, account: String) throws
}

enum SecureCredentialStoreError: LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown Keychain error"
            return "Keychain error \(status): \(message)"
        }
    }
}

struct KeychainCredentialStore: SecureCredentialStore {
    func credential(service: String, account: String) throws -> Data? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw SecureCredentialStoreError.keychain(status) }
        return result as? Data
    }

    func setCredential(_ credential: Data, service: String, account: String) throws {
        let query = baseQuery(service: service, account: account)
        let attributes = [kSecValueData as String: credential]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw SecureCredentialStoreError.keychain(updateStatus)
        }
        var item = query
        item[kSecValueData as String] = credential
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw SecureCredentialStoreError.keychain(addStatus) }
    }

    func removeCredential(service: String, account: String) throws {
        let status = SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureCredentialStoreError.keychain(status)
        }
    }

    private func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
