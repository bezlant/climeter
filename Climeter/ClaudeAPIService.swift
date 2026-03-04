import Foundation

enum ClaudeAPIService {
    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    static func fetchUsage(credential: Credential) async throws -> UsageData {
        let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("claude-code/2.0.32", forHTTPHeaderField: "User-Agent")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw ClaudeAPIError.httpError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let usageData = try decoder.decode(UsageData.self, from: data)
            return usageData
        } catch {
            throw ClaudeAPIError.decodingError(error)
        }
    }

    static func refreshToken(_ credential: Credential) async throws -> Credential {
        let url = URL(string: "https://console.anthropic.com/v1/oauth/token")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": credential.refreshToken
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw ClaudeAPIError.tokenRefreshFailed(httpResponse.statusCode)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let refreshToken = json["refresh_token"] as? String else {
            throw ClaudeAPIError.invalidResponse
        }

        let expiresIn = json["expires_in"] as? TimeInterval ?? 3600
        var refreshed = credential
        refreshed.accessToken = accessToken
        refreshed.refreshToken = refreshToken
        refreshed.expiresAt = Date.now.addingTimeInterval(expiresIn)
        return refreshed
    }
}

enum ClaudeAPIError: Error {
    case invalidCredential
    case invalidResponse
    case httpError(Int)
    case decodingError(Error)
    case tokenRefreshFailed(Int)
}
