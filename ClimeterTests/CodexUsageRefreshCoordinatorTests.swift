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

    func test_staleThresholdIsThreeBaseIntervals() {
        XCTAssertEqual(
            CodexUsageRefreshCoordinator.staleThreshold,
            CodexUsageRefreshCoordinator.baseInterval * 3
        )
    }
}
