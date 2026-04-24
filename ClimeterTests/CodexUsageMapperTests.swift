import XCTest
@testable import Climeter

final class CodexUsageMapperTests: XCTestCase {
    func test_mapsPrimaryAndSecondaryByWindowDuration() throws {
        let response = CodexUsageResponse(
            planType: "pro",
            rateLimit: CodexRateLimitDetails(
                primaryWindow: CodexWindowSnapshot(usedPercent: 25, resetAt: 1_777_100_000, limitWindowSeconds: 18_000),
                secondaryWindow: CodexWindowSnapshot(usedPercent: 40, resetAt: 1_777_600_000, limitWindowSeconds: 604_800)
            ),
            credits: nil
        )

        let usage = try CodexUsageMapper.map(response)

        XCTAssertEqual(usage.fiveHour.utilization, 25)
        XCTAssertEqual(usage.sevenDay.utilization, 40)
        XCTAssertEqual(usage.fiveHour.resetsAt, Date(timeIntervalSince1970: 1_777_100_000))
        XCTAssertEqual(usage.sevenDay.resetsAt, Date(timeIntervalSince1970: 1_777_600_000))
    }

    func test_mapsReversedWindowsByDuration() throws {
        let response = CodexUsageResponse(
            planType: "pro",
            rateLimit: CodexRateLimitDetails(
                primaryWindow: CodexWindowSnapshot(usedPercent: 70, resetAt: 1_777_600_000, limitWindowSeconds: 604_800),
                secondaryWindow: CodexWindowSnapshot(usedPercent: 15, resetAt: 1_777_100_000, limitWindowSeconds: 18_000)
            ),
            credits: nil
        )

        let usage = try CodexUsageMapper.map(response)

        XCTAssertEqual(usage.fiveHour.utilization, 15)
        XCTAssertEqual(usage.sevenDay.utilization, 70)
    }

    func test_clampsPercentages() throws {
        let response = CodexUsageResponse(
            planType: "pro",
            rateLimit: CodexRateLimitDetails(
                primaryWindow: CodexWindowSnapshot(usedPercent: -5, resetAt: 1_777_100_000, limitWindowSeconds: 18_000),
                secondaryWindow: CodexWindowSnapshot(usedPercent: 140, resetAt: 1_777_600_000, limitWindowSeconds: 604_800)
            ),
            credits: nil
        )

        let usage = try CodexUsageMapper.map(response)

        XCTAssertEqual(usage.fiveHour.utilization, 0)
        XCTAssertEqual(usage.sevenDay.utilization, 100)
    }

    func test_missingWindowsThrowsNoUsage() {
        let response = CodexUsageResponse(planType: "pro", rateLimit: nil, credits: nil)

        XCTAssertThrowsError(try CodexUsageMapper.map(response)) { error in
            XCTAssertEqual(error as? CodexUsageMapperError, .missingWindows)
        }
    }
}
