import Foundation
import Security

enum KeychainService {
    private static let serviceName = "com.bezlant.climeter"

    static func save(_ sessionKey: String, for profileID: UUID) throws {
        guard let data = sessionKey.data(using: .utf8) else {
            throw KeychainError.invalidData
        }

        let account = profileID.uuidString
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data

            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unableToSave(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.unableToSave(updateStatus)
        }
    }

    static func read(for profileID: UUID) throws -> String? {
        let account = profileID.uuidString
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.unableToRead(status)
        }

        guard let data = result as? Data,
              let sessionKey = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }

        return sessionKey
    }

    static func delete(for profileID: UUID) throws {
        let account = profileID.uuidString
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)

        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.unableToDelete(status)
        }
    }
}

enum KeychainError: Error {
    case invalidData
    case unableToSave(OSStatus)
    case unableToRead(OSStatus)
    case unableToDelete(OSStatus)
}
