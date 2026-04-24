import XCTest
@testable import Climeter

final class CodexUsageRefreshCoordinatorTests: XCTestCase {
    func test_describeErrorForMissingLogin() {
        XCTAssertEqual(
            CodexUsageRefreshCoordinator.describeError(CodexCredentialStoreError.notFound("/tmp/auth.json")),
            "Run `codex login`"
        )
    }

    func test_describeErrorForAPIKeyMode() {
        XCTAssertEqual(
            CodexUsageRefreshCoordinator.describeError(CodexUsageRefreshError.apiKeyMode),
            "Codex API key mode: plan limits unavailable"
        )
    }

    func test_describeErrorForUnauthorized() {
        XCTAssertEqual(
            CodexUsageRefreshCoordinator.describeError(CodexAPIError.unauthorized),
            "Codex session expired. Run `codex login`"
        )
    }

    func test_describeErrorForRateLimit() {
        XCTAssertEqual(
            CodexUsageRefreshCoordinator.describeError(CodexAPIError.httpError(429)),
            "Codex rate limited - retrying soon"
        )
    }

    func test_describeErrorForOtherHTTPStatus() {
        XCTAssertEqual(
            CodexUsageRefreshCoordinator.describeError(CodexAPIError.httpError(500)),
            "Codex HTTP 500"
        )
    }

    func test_describeErrorForUsageFormatChanges() {
        XCTAssertEqual(
            CodexUsageRefreshCoordinator.describeError(CodexAPIError.decodingError),
            "Codex usage format changed"
        )
        XCTAssertEqual(
            CodexUsageRefreshCoordinator.describeError(CodexUsageMapperError.missingWindows),
            "Codex usage format changed"
        )
    }

    func test_describeErrorForInvalidAuthJSON() {
        XCTAssertEqual(
            CodexUsageRefreshCoordinator.describeError(CodexCredentialError.invalidJSON),
            "Codex auth file unreadable. Run `codex login`"
        )
    }

    func test_staleThresholdIsThreeBaseIntervals() {
        XCTAssertEqual(
            CodexUsageRefreshCoordinator.staleThreshold,
            CodexUsageRefreshCoordinator.baseInterval * 3
        )
    }
}
