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
}
