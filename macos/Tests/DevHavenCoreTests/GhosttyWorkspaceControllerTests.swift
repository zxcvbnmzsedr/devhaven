import XCTest
@testable import DevHavenCore

@MainActor
final class GhosttyWorkspaceControllerTests: XCTestCase {
    func testControllerStartsWithSingleSelectedTabAndPaneProjection() {
        let controller = GhosttyWorkspaceController(projectPath: "/tmp/devhaven", workspaceId: "workspace:test")

        XCTAssertEqual(controller.workspaceId, "workspace:test")
        XCTAssertEqual(controller.tabs.count, 1)
        XCTAssertEqual(controller.selectedTab?.title, "终端1")
        XCTAssertEqual(controller.selectedPane?.request.projectPath, "/tmp/devhaven")
        XCTAssertEqual(controller.paneCount, 1)
    }

    func testControllerMutationsOnlyUpdateProjectionInsideController() throws {
        let controller = GhosttyWorkspaceController(projectPath: "/tmp/devhaven", workspaceId: "workspace:test")
        let firstTabID = try XCTUnwrap(controller.selectedTab?.id)
        let firstPaneID = try XCTUnwrap(controller.selectedPane?.id)

        _ = controller.createTab()
        XCTAssertEqual(controller.tabs.count, 2)

        controller.selectTab(firstTabID)
        _ = controller.splitFocusedPane(direction: .right)
        XCTAssertEqual(controller.selectedTab?.leaves.count, 2)
        XCTAssertNotEqual(controller.selectedTab?.focusedPaneId, firstPaneID)
    }

    func testControllerClosingLastPaneCreatesReplacementTab() throws {
        let controller = GhosttyWorkspaceController(projectPath: "/tmp/devhaven", workspaceId: "workspace:test")
        let originalTabID = try XCTUnwrap(controller.selectedTab?.id)
        let originalPaneID = try XCTUnwrap(controller.selectedPane?.id)

        controller.closePane(originalPaneID)

        XCTAssertEqual(controller.tabs.count, 1)
        XCTAssertNotEqual(controller.selectedTab?.id, originalTabID)
        XCTAssertEqual(controller.selectedTab?.leaves.count, 1)
    }

    func testControllerRuntimeTitleCannotOverrideStableWorkspaceTabTitle() throws {
        let controller = GhosttyWorkspaceController(projectPath: "/tmp/devhaven", workspaceId: "workspace:test")
        let tabID = try XCTUnwrap(controller.selectedTab?.id)

        controller.updateTitle(for: tabID, title: "/tmp/devhaven")

        XCTAssertEqual(controller.selectedTab?.title, "终端1")
    }
}
