import Foundation

enum CodexCredentialStoreError: Error, Equatable {
    case notFound(String)
}

enum CodexCredentialStore {
    static func codexHome(env: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let override = env["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }

    static func authFileURL(env: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        codexHome(env: env).appendingPathComponent("auth.json")
    }

    static func load(env: [String: String] = ProcessInfo.processInfo.environment) throws -> CodexCredential {
        let url = authFileURL(env: env)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CodexCredentialStoreError.notFound(url.path)
        }
        return try CodexCredential.parse(data: Data(contentsOf: url))
    }

    static func save(_ credential: CodexCredential, env: [String: String] = ProcessInfo.processInfo.environment) throws {
        let url = authFileURL(env: env)
        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: url),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }

        var tokens = (json["tokens"] as? [String: Any]) ?? [:]
        tokens["access_token"] = credential.accessToken
        tokens["refresh_token"] = credential.refreshToken
        if let idToken = credential.idToken { tokens["id_token"] = idToken }
        if let accountID = credential.accountID { tokens["account_id"] = accountID }
        json["tokens"] = tokens
        json["last_refresh"] = ISO8601DateFormatter().string(from: Date())

        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }
}
