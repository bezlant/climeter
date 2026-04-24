import XCTest
@testable import Climeter

final class ClimeterTests: XCTestCase {
    func test_testTargetIsWired() {
        XCTAssertEqual(UsageWindow(utilization: 12, resetsAt: nil).utilization, 12)
    }
}
