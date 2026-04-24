import Foundation

enum CodexAuthMode: Equatable {
    case chatGPT
    case apiKey
}

enum CodexCredentialError: Error, Equatable {
    case invalidJSON
    case missingTokens
}

struct CodexCredential: Equatable {
    var accessToken: String
    var refreshToken: String
    var idToken: String?
    var accountID: String?
    var lastRefresh: Date?
    var authMode: CodexAuthMode

    func needsRefresh(now: Date = Date()) -> Bool {
        guard authMode == .chatGPT else { return false }
        guard let lastRefresh else { return true }
        return now.timeIntervalSince(lastRefresh) > 8 * 24 * 60 * 60
    }

    static func parse(data: Data) throws -> CodexCredential {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexCredentialError.invalidJSON
        }

        if let apiKey = json["OPENAI_API_KEY"] as? String,
           !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return CodexCredential(
                accessToken: apiKey,
                refreshToken: "",
                idToken: nil,
                accountID: nil,
                lastRefresh: nil,
                authMode: .apiKey
            )
        }

        guard let tokens = json["tokens"] as? [String: Any] else {
            throw CodexCredentialError.missingTokens
        }
        guard let accessToken = string(in: tokens, snake: "access_token", camel: "accessToken"),
              let refreshToken = string(in: tokens, snake: "refresh_token", camel: "refreshToken"),
              !accessToken.isEmpty else {
            throw CodexCredentialError.missingTokens
        }

        return CodexCredential(
            accessToken: accessToken,
            refreshToken: refreshToken,
            idToken: string(in: tokens, snake: "id_token", camel: "idToken"),
            accountID: string(in: tokens, snake: "account_id", camel: "accountId"),
            lastRefresh: parseDate(json["last_refresh"]),
            authMode: .chatGPT
        )
    }

    private static func string(in dictionary: [String: Any], snake: String, camel: String) -> String? {
        if let value = dictionary[snake] as? String, !value.isEmpty { return value }
        if let value = dictionary[camel] as? String, !value.isEmpty { return value }
        return nil
    }

    private static func parseDate(_ raw: Any?) -> Date? {
        guard let value = raw as? String, !value.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
