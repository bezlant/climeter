import Foundation
import Security

enum ClaudeCodeSyncService {
    private static let serviceName = "Claude Code-credentials"
    private static let account = NSUserName()

    static func readCLICredential() -> Credential? {
        guard let raw = readCLICredentialRaw() else { return nil }
        return Credential(jsonString: raw)
    }

    static func readCLICredentialRaw() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let credential = String(data: data, encoding: .utf8) else {
            return nil
        }

        return credential
    }

    static func writeCLICredential(_ credential: Credential) {
        let jsonString = credential.toJSONString()
        guard let data = jsonString.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]

        // Try updating in-place first to preserve existing ACL (including
        // any "Always Allow" grants the user has given to Claude Code CLI).
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            // Item doesn't exist yet — create with an ACL that trusts
            // both Climeter and /usr/bin/security.
            var addQuery = query
            addQuery[kSecValueData as String] = data

            if let access = makeSharedAccess() {
                addQuery[kSecAttrAccess as String] = access
            }

            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    private static func makeSharedAccess() -> SecAccess? {
        var trustedApps: [SecTrustedApplication] = []

        var selfApp: SecTrustedApplication?
        SecTrustedApplicationCreateFromPath(nil, &selfApp)
        if let selfApp { trustedApps.append(selfApp) }

        var securityTool: SecTrustedApplication?
        SecTrustedApplicationCreateFromPath("/usr/bin/security", &securityTool)
        if let securityTool { trustedApps.append(securityTool) }

        var access: SecAccess?
        SecAccessCreate(serviceName as CFString, trustedApps as CFArray, &access)
        return access
    }
}
