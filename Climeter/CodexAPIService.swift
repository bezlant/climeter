import Foundation

struct CodexUsageResponse: Decodable, Equatable {
    let planType: String?
    let rateLimit: CodexRateLimitDetails?
    let credits: CodexCreditDetails?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case credits
    }
}

struct CodexRateLimitDetails: Decodable, Equatable {
    let primaryWindow: CodexWindowSnapshot?
    let secondaryWindow: CodexWindowSnapshot?

    enum CodingKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }
}

struct CodexWindowSnapshot: Decodable, Equatable {
    let usedPercent: Int
    let resetAt: Int
    let limitWindowSeconds: Int

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case resetAt = "reset_at"
        case limitWindowSeconds = "limit_window_seconds"
    }
}

struct CodexCreditDetails: Decodable, Equatable {
    let hasCredits: Bool
    let unlimited: Bool
    let balance: Double?

    enum CodingKeys: String, CodingKey {
        case hasCredits = "has_credits"
        case unlimited
        case balance
    }
}

enum CodexAPIError: Error, Equatable {
    case invalidResponse
    case httpError(Int)
    case unauthorized
    case decodingError
}

enum CodexAPIService {
    private static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    static func makeUsageRequest(accessToken: String, accountID: String?) -> URLRequest {
        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Climeter", forHTTPHeaderField: "User-Agent")
        if let accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        return request
    }

    static func decodeUsageResponse(_ data: Data) throws -> CodexUsageResponse {
        do {
            return try JSONDecoder().decode(CodexUsageResponse.self, from: data)
        } catch {
            throw CodexAPIError.decodingError
        }
    }

    static func fetchUsage(credential: CodexCredential) async throws -> UsageData {
        Log.api.info("codexUsage: GET /backend-api/wham/usage")
        let request = makeUsageRequest(accessToken: credential.accessToken, accountID: credential.accountID)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            Log.api.warning("codexUsage: invalid response")
            throw CodexAPIError.invalidResponse
        }
        Log.api.info("codexUsage: HTTP \(http.statusCode)")
        switch http.statusCode {
        case 200...299:
            do {
                return try CodexUsageMapper.map(decodeUsageResponse(data))
            } catch CodexAPIError.decodingError {
                Log.api.warning("codexUsage: decode failed")
                throw CodexAPIError.decodingError
            } catch CodexUsageMapperError.missingWindows {
                Log.api.warning("codexUsage: missing usage windows")
                throw CodexUsageMapperError.missingWindows
            }
        case 401, 403:
            throw CodexAPIError.unauthorized
        default:
            throw CodexAPIError.httpError(http.statusCode)
        }
    }
}

enum CodexTokenRefresher {
    private static let refreshURL = URL(string: "https://auth.openai.com/oauth/token")!
    private static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"

    static func makeRefreshRequest(refreshToken: String) throws -> URLRequest {
        var request = URLRequest(url: refreshURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "scope": "openid profile email"
        ])
        return request
    }

    static func refresh(_ credential: CodexCredential) async throws -> CodexCredential {
        guard !credential.refreshToken.isEmpty else { return credential }
        Log.api.info("codexRefresh: POST /oauth/token")
        let request = try makeRefreshRequest(refreshToken: credential.refreshToken)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            Log.api.warning("codexRefresh: invalid response")
            throw CodexAPIError.invalidResponse
        }
        Log.api.info("codexRefresh: HTTP \(http.statusCode)")
        guard http.statusCode == 200 else {
            if http.statusCode == 401 { throw CodexAPIError.unauthorized }
            throw CodexAPIError.httpError(http.statusCode)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Log.api.warning("codexRefresh: invalid JSON")
            throw CodexAPIError.invalidResponse
        }
        return CodexCredential(
            accessToken: json["access_token"] as? String ?? credential.accessToken,
            refreshToken: json["refresh_token"] as? String ?? credential.refreshToken,
            idToken: json["id_token"] as? String ?? credential.idToken,
            accountID: credential.accountID,
            lastRefresh: Date(),
            authMode: .chatGPT
        )
    }
}
