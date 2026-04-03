import XCTest
@testable import DevHavenCore

@MainActor
final class NativeAppViewModelWorkspaceBrowserTabTests: XCTestCase {
    func testOpenWorkspaceBrowserTabCreatesAndSelectsBrowserPaneItem() throws {
        let projectPath = "/tmp/workspace-browser-pane-item"
        let controller = GhosttyWorkspaceController(projectPath: projectPath)
        let selectedTerminalTabID = try XCTUnwrap(controller.selectedTabId)
        let selectedPaneID = try XCTUnwrap(controller.selectedPane?.id)

        let viewModel = NativeAppViewModel()
        viewModel.openWorkspaceSessions = [
            OpenWorkspaceSessionState(
                projectPath: projectPath,
                controller: controller
            )
        ]
        viewModel.activeWorkspaceProjectPath = projectPath

        let browserItem = try XCTUnwrap(
            viewModel.openWorkspaceBrowserTab(
                urlString: "http://localhost:3000",
                in: projectPath
            )
        )

        let browserState = try XCTUnwrap(
            viewModel.workspaceBrowserItemState(for: projectPath, itemID: browserItem.id)
        )

        XCTAssertEqual(controller.selectedTabId, selectedTerminalTabID)
        XCTAssertEqual(controller.selectedPane?.id, selectedPaneID)
        XCTAssertEqual(controller.selectedPane?.selectedItem?.id, browserItem.id)
        XCTAssertEqual(controller.selectedPane?.selectedBrowserState?.id, browserItem.id)
        XCTAssertEqual(browserState.urlString, "http://localhost:3000")
        XCTAssertEqual(
            viewModel.workspacePresentedTabSnapshot(for: projectPath).selection,
            .terminal(selectedTerminalTabID)
        )
        XCTAssertEqual(viewModel.workspaceFocusedArea, .browserPaneItem(browserItem.id))
    }

    func testCloseSelectedBrowserPaneItemFallsBackToTerminalItem() throws {
        let projectPath = "/tmp/workspace-browser-close"
        let controller = GhosttyWorkspaceController(projectPath: projectPath)
        let selectedTerminalTabID = try XCTUnwrap(controller.selectedTabId)
        let terminalItemID = try XCTUnwrap(controller.selectedPane?.selectedItem?.id)

        let viewModel = NativeAppViewModel()
        viewModel.openWorkspaceSessions = [
            OpenWorkspaceSessionState(
                projectPath: projectPath,
                controller: controller
            )
        ]
        viewModel.activeWorkspaceProjectPath = projectPath

        let browserItem = try XCTUnwrap(viewModel.openWorkspaceBrowserTab(in: projectPath))
        viewModel.closeWorkspaceBrowserTab(browserItem.id, in: projectPath)

        XCTAssertNil(viewModel.workspaceBrowserItemState(for: projectPath, itemID: browserItem.id))
        XCTAssertEqual(controller.selectedPane?.selectedItem?.id, terminalItemID)
        XCTAssertNotNil(controller.selectedPane?.selectedTerminalRequest)
        XCTAssertNil(controller.selectedPane?.selectedBrowserState)
        XCTAssertEqual(
            viewModel.workspacePresentedTabSnapshot(for: projectPath).selection,
            .terminal(selectedTerminalTabID)
        )
        XCTAssertEqual(viewModel.workspaceFocusedArea, .terminal)
    }

    func testUpdateWorkspaceBrowserTabStateUpdatesBrowserPaneItemState() throws {
        let projectPath = "/tmp/workspace-browser-update"
        let controller = GhosttyWorkspaceController(projectPath: projectPath)

        let viewModel = NativeAppViewModel()
        viewModel.openWorkspaceSessions = [
            OpenWorkspaceSessionState(
                projectPath: projectPath,
                controller: controller
            )
        ]
        viewModel.activeWorkspaceProjectPath = projectPath

        let browserItem = try XCTUnwrap(viewModel.openWorkspaceBrowserTab(in: projectPath))

        _ = viewModel.updateWorkspaceBrowserTabState(
            browserItem.id,
            in: projectPath,
            title: "DevHaven Docs",
            urlString: "https://example.com/docs",
            isLoading: true
        )

        let browserState = try XCTUnwrap(
            viewModel.workspaceBrowserItemState(for: projectPath, itemID: browserItem.id)
        )
        XCTAssertEqual(browserState.title, "DevHaven Docs")
        XCTAssertEqual(browserState.urlString, "https://example.com/docs")
        XCTAssertTrue(browserState.isLoading)
        XCTAssertEqual(controller.selectedPane?.selectedItem?.title, "DevHaven Docs")
    }
}
