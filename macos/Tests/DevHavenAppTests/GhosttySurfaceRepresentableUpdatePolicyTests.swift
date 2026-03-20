import XCTest
@testable import DevHavenApp

final class GhosttySurfaceRepresentableUpdatePolicyTests: XCTestCase {
    func testRepresentableUpdateDoesNotApplyHostSyncByDefault() {
        XCTAssertFalse(GhosttySurfaceRepresentableUpdatePolicy.shouldApplyLatestModelStateOnUpdate)
    }
}
