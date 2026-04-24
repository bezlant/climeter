import XCTest
@testable import Climeter

final class CodexAPIServiceTests: XCTestCase {
    func test_usageRequestContainsBearerAndAccountHeaders() throws {
        let request = CodexAPIService.makeUsageRequest(
            accessToken: "access-token",
            accountID: "account-id"
        )

        XCTAssertEqual(request.url?.absoluteString, "https://chatgpt.com/backend-api/wham/usage")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "ChatGPT-Account-Id"), "account-id")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func test_usageRequestOmitsEmptyAccountHeader() throws {
        let request = CodexAPIService.makeUsageRequest(accessToken: "access-token", accountID: nil)

        XCTAssertNil(request.value(forHTTPHeaderField: "ChatGPT-Account-Id"))
    }

    func test_decodeUsageResponse() throws {
        let data = Data("""
        {
          "plan_type": "pro",
          "rate_limit": {
            "primary_window": { "used_percent": 11, "reset_at": 1777100000, "limit_window_seconds": 18000 },
            "secondary_window": { "used_percent": 22, "reset_at": 1777600000, "limit_window_seconds": 604800 }
          },
          "credits": { "has_credits": true, "unlimited": false, "balance": 12.5 }
        }
        """.utf8)

        let decoded = try CodexAPIService.decodeUsageResponse(data)

        XCTAssertEqual(decoded.planType, "pro")
        XCTAssertEqual(decoded.rateLimit?.primaryWindow?.usedPercent, 11)
        XCTAssertEqual(decoded.credits?.balance, 12.5)
    }

    func test_refreshRequestBody() throws {
        let request = try CodexTokenRefresher.makeRefreshRequest(refreshToken: "refresh-token")

        XCTAssertEqual(request.url?.absoluteString, "https://auth.openai.com/oauth/token")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(json["client_id"], "app_EMoamEEZ73f0CkXaXp7hrann")
        XCTAssertEqual(json["grant_type"], "refresh_token")
        XCTAssertEqual(json["refresh_token"], "refresh-token")
        XCTAssertEqual(json["scope"], "openid profile email")
    }
}
