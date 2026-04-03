import XCTest
@testable import DevHavenCore

@MainActor
final class GhosttyWorkspaceControllerBrowserStateTests: XCTestCase {
    func testUpdateBrowserStateDoesNotEmitChangeWhenStateUnchanged() throws {
        let controller = GhosttyWorkspaceController(projectPath: "/tmp/browser-noop")
        let paneID = try XCTUnwrap(controller.selectedPane?.id)
        let item = try XCTUnwrap(controller.createBrowserItem(inPane: paneID))

        var changeCount = 0
        controller.onChange = {
            changeCount += 1
        }

        _ = controller.updateBrowserState(
            inPane: paneID,
            itemID: item.id,
            title: "浏览器",
            urlString: "",
            isLoading: false
        )

        XCTAssertEqual(changeCount, 0)
    }

    func testUpdateBrowserStateEmitsChangeWhenStateActuallyChanges() throws {
        let controller = GhosttyWorkspaceController(projectPath: "/tmp/browser-change")
        let paneID = try XCTUnwrap(controller.selectedPane?.id)
        let item = try XCTUnwrap(controller.createBrowserItem(inPane: paneID))

        var changeCount = 0
        controller.onChange = {
            changeCount += 1
        }

        let state = controller.updateBrowserState(
            inPane: paneID,
            itemID: item.id,
            title: "DevHaven",
            urlString: "https://example.com",
            isLoading: true
        )

        XCTAssertEqual(changeCount, 1)
        XCTAssertEqual(state?.title, "DevHaven")
        XCTAssertEqual(state?.urlString, "https://example.com")
        XCTAssertEqual(state?.isLoading, true)
    }
}
