import Foundation

enum ClaudeAPIService {
    static func fetchUsage(credential: String) async throws -> UsageData {
        let accessToken = try extractAccessToken(from: credential)
        let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
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

    private static func extractAccessToken(from credential: String) throws -> String {
        guard let data = credential.data(using: .utf8) else {
            throw ClaudeAPIError.invalidCredential
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let claudeAiOauth = json["claudeAiOauth"] as? [String: Any],
              let accessToken = claudeAiOauth["accessToken"] as? String else {
            throw ClaudeAPIError.invalidCredential
        }

        return accessToken
    }
}

enum ClaudeAPIError: Error {
    case invalidCredential
    case invalidResponse
    case httpError(Int)
    case decodingError(Error)
}
