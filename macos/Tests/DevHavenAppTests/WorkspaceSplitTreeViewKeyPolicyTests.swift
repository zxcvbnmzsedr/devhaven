import XCTest
@testable import DevHavenApp

final class WorkspaceSplitTreeViewKeyPolicyTests: XCTestCase {
    func testRootTreeDoesNotForceStructuralRemount() {
        XCTAssertFalse(WorkspaceSplitTreeViewKeyPolicy.shouldKeyRootByStructuralIdentity)
    }

    func testSplitSubtreeDoesNotForceStructuralRemount() {
        XCTAssertFalse(WorkspaceSplitTreeViewKeyPolicy.shouldKeySplitSubtreeByStructuralIdentity)
    }
}
