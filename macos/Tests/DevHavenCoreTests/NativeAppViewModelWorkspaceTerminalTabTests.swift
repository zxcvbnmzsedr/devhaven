import XCTest
@testable import DevHavenCore

@MainActor
final class NativeAppViewModelWorkspaceTerminalTabTests: XCTestCase {
    func testCreateWorkspaceTerminalTabCreatesAndSelectsNewTerminalTab() throws {
        let projectPath = "/tmp/workspace-terminal-tabs"
        let controller = GhosttyWorkspaceController(projectPath: projectPath)
        let initialTabID = try XCTUnwrap(controller.selectedTabId)

        let viewModel = NativeAppViewModel()
        viewModel.openWorkspaceSessions = [
            OpenWorkspaceSessionState(
                projectPath: projectPath,
                controller: controller
            )
        ]
        viewModel.activeWorkspaceProjectPath = projectPath

        let createdTab = try XCTUnwrap(viewModel.createWorkspaceTerminalTab())

        XCTAssertNotEqual(createdTab.id, initialTabID)
        XCTAssertEqual(controller.selectedTabId, createdTab.id)
        XCTAssertEqual(
            viewModel.workspacePresentedTabSnapshot(for: projectPath).selection,
            .terminal(createdTab.id)
        )
        XCTAssertEqual(viewModel.workspaceFocusedArea, .terminal)
    }

    func testCreateWorkspaceTerminalTabWithoutActiveWorkspaceReturnsNil() {
        let viewModel = NativeAppViewModel()

        XCTAssertNil(viewModel.createWorkspaceTerminalTab())
    }

    func testActiveWorkspaceLaunchRequestChangesSurfaceWithinSamePane() throws {
        let projectPath = "/tmp/workspace-terminal-pane-items"
        let controller = GhosttyWorkspaceController(projectPath: projectPath)
        let initialRequest = try XCTUnwrap(controller.selectedPane?.request)

        let viewModel = NativeAppViewModel()
        viewModel.openWorkspaceSessions = [
            OpenWorkspaceSessionState(
                projectPath: projectPath,
                controller: controller
            )
        ]
        viewModel.activeWorkspaceProjectPath = projectPath

        let createdItem = try XCTUnwrap(controller.createTerminalItem(inPane: initialRequest.paneId))
        let updatedRequest = try XCTUnwrap(viewModel.activeWorkspaceLaunchRequest)

        XCTAssertEqual(updatedRequest.paneId, initialRequest.paneId)
        XCTAssertEqual(updatedRequest.surfaceId, createdItem.id)
        XCTAssertNotEqual(updatedRequest.surfaceId, initialRequest.surfaceId)
    }
}
