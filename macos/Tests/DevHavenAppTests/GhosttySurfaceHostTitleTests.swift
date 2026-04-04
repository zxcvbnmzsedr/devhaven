import XCTest
@testable import DevHavenApp
@testable import DevHavenCore

@MainActor
final class GhosttySurfaceHostTitleTests: XCTestCase {
    func testApplyRuntimeTitleRestoresNormalizedPathAfterCommandTitle() {
        let projectPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("WebstormProjects/DevHaven")
            .path

        var callbackTitles: [String] = []
        let model = GhosttySurfaceHostModel(
            request: WorkspaceTerminalLaunchRequest(
                projectPath: projectPath,
                workspaceId: "workspace:test",
                tabId: "tab:test",
                paneId: "pane:test",
                surfaceId: "surface:test",
                terminalSessionId: "session:test"
            ),
            onTabTitleChange: { callbackTitles.append($0) }
        )
        model.surfaceWorkingDirectory = projectPath
        model.surfaceTitle = "pwd"

        let applied = model.applyRuntimeTitle("zhaotianzeng@Mac-mini:~/WebstormProjects/DevHaven")

        XCTAssertEqual(applied, "~/WebstormProjects/DevHaven")
        XCTAssertEqual(model.surfaceTitle, "~/WebstormProjects/DevHaven")
        XCTAssertEqual(callbackTitles, ["~/WebstormProjects/DevHaven"])
    }
}
