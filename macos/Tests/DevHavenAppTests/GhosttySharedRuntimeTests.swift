import XCTest
@testable import DevHavenApp
@testable import DevHavenCore

@MainActor
final class GhosttySharedRuntimeTests: XCTestCase {
    func testHostModelInitializesWithRequestOnly() {
        let request = WorkspaceTerminalLaunchRequest(
            projectPath: "/tmp/devhaven-project",
            workspaceId: "workspace:test",
            tabId: "tab:test",
            paneId: "pane:test",
            surfaceId: "surface:test",
            terminalSessionId: "session:test"
        )

        let model = GhosttySurfaceHostModel(request: request)

        XCTAssertEqual(model.surfaceWorkingDirectory, "/tmp/devhaven-project")
        XCTAssertNotNil(model.terminalRuntime)
    }
}
