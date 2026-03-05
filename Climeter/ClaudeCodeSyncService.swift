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

        // Delete and re-create with an ACL that includes /usr/bin/security,
        // so Claude Code CLI won't trigger a keychain prompt.
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data

        if let access = makeSharedAccess() {
            addQuery[kSecAttrAccess as String] = access
        }

        SecItemAdd(addQuery as CFDictionary, nil)
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
