import XCTest
@testable import Climeter

final class CodexCredentialTests: XCTestCase {
    func test_parseOAuthSnakeCaseAuthJSON() throws {
        let data = Data("""
        {
          "tokens": {
            "access_token": "access-1",
            "refresh_token": "refresh-1",
            "id_token": "id-1",
            "account_id": "account-1"
          },
          "last_refresh": "2026-04-23T12:00:00Z"
        }
        """.utf8)

        let credential = try CodexCredential.parse(data: data)

        XCTAssertEqual(credential.authMode, .chatGPT)
        XCTAssertEqual(credential.accessToken, "access-1")
        XCTAssertEqual(credential.refreshToken, "refresh-1")
        XCTAssertEqual(credential.idToken, "id-1")
        XCTAssertEqual(credential.accountID, "account-1")
        XCTAssertFalse(credential.needsRefresh(now: ISO8601DateFormatter().date(from: "2026-04-24T12:00:00Z")!))
    }

    func test_parseOAuthCamelCaseAuthJSON() throws {
        let data = Data("""
        {
          "tokens": {
            "accessToken": "access-2",
            "refreshToken": "refresh-2",
            "idToken": "id-2",
            "accountId": "account-2"
          },
          "last_refresh": "2026-04-01T12:00:00Z"
        }
        """.utf8)

        let credential = try CodexCredential.parse(data: data)

        XCTAssertEqual(credential.authMode, .chatGPT)
        XCTAssertEqual(credential.accessToken, "access-2")
        XCTAssertEqual(credential.refreshToken, "refresh-2")
        XCTAssertEqual(credential.idToken, "id-2")
        XCTAssertEqual(credential.accountID, "account-2")
        XCTAssertTrue(credential.needsRefresh(now: ISO8601DateFormatter().date(from: "2026-04-24T12:00:00Z")!))
    }

    func test_parseAPIKeyMode() throws {
        let data = Data(#"{ "OPENAI_API_KEY": "sk-test" }"#.utf8)

        let credential = try CodexCredential.parse(data: data)

        XCTAssertEqual(credential.authMode, .apiKey)
        XCTAssertEqual(credential.accessToken, "sk-test")
        XCTAssertEqual(credential.refreshToken, "")
    }

    func test_missingTokensThrows() {
        let data = Data(#"{ "tokens": {} }"#.utf8)

        XCTAssertThrowsError(try CodexCredential.parse(data: data)) { error in
            XCTAssertEqual(error as? CodexCredentialError, .missingTokens)
        }
    }
}
