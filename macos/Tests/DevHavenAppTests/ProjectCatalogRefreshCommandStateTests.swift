import XCTest
@testable import DevHavenApp

final class ProjectCatalogRefreshCommandStateTests: XCTestCase {
    func testIdleStateShowsRefreshProjectCommand() {
        let state = projectCatalogRefreshCommandState(isRefreshing: false)

        XCTAssertEqual(state.title, "刷新项目")
        XCTAssertFalse(state.isDisabled)
    }

    func testRefreshingStateShowsBusyCommandAndDisablesShortcutTarget() {
        let state = projectCatalogRefreshCommandState(isRefreshing: true)

        XCTAssertEqual(state.title, "正在刷新项目…")
        XCTAssertTrue(state.isDisabled)
    }
}
