import XCTest
@testable import DevHavenCore

final class WorkspaceSubsystemTests: XCTestCase {
    func testWorkspaceTerminalLaunchRequestBuildsExpectedEnvironment() {
        let request = WorkspaceTerminalLaunchRequest(
            projectPath: "/tmp/devhaven",
            workspaceId: "workspace:test",
            tabId: "tab:test",
            paneId: "pane:test",
            surfaceId: "surface:test",
            terminalSessionId: "session:test"
        )

        XCTAssertEqual(request.projectPath, "/tmp/devhaven")
        XCTAssertEqual(request.terminalRuntime, "ghostty")
        XCTAssertEqual(request.environment["DEVHAVEN_PROJECT_PATH"], "/tmp/devhaven")
        XCTAssertEqual(request.environment["DEVHAVEN_WORKSPACE_ID"], "workspace:test")
        XCTAssertEqual(request.environment["DEVHAVEN_TAB_ID"], "tab:test")
        XCTAssertEqual(request.environment["DEVHAVEN_PANE_ID"], "pane:test")
        XCTAssertEqual(request.environment["DEVHAVEN_SURFACE_ID"], "surface:test")
        XCTAssertEqual(request.environment["DEVHAVEN_TERMINAL_SESSION_ID"], "session:test")
        XCTAssertEqual(request.environment["DEVHAVEN_TERMINAL_RUNTIME"], "ghostty")
    }
}
