import XCTest
@testable import DevHavenCore

final class WorkspaceTabTitlePolicyTests: XCTestCase {
    func testDefaultTitleUsesCompactTerminalNumbering() {
        XCTAssertEqual(WorkspaceTabTitlePolicy.defaultTitle(for: 1), "终端1")
        XCTAssertEqual(WorkspaceTabTitlePolicy.defaultTitle(for: 4), "终端4")
    }

    func testRuntimeShellTitleDoesNotOverrideStableWorkspaceTitle() {
        XCTAssertEqual(
            WorkspaceTabTitlePolicy.resolveRuntimeTitle(currentTitle: "终端2", runtimeTitle: "zhaotianzeng@Mac-mini:~/repo"),
            "终端2"
        )
        XCTAssertEqual(
            WorkspaceTabTitlePolicy.resolveRuntimeTitle(currentTitle: "终端3", runtimeTitle: "/Users/zhaotianzeng/Documents/repo"),
            "终端3"
        )
    }
}
