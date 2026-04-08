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

    func testCurrentVisibleTextUsesAutosaveCacheButFlushCanForceRefresh() {
        let model = GhosttySurfaceHostModel(
            request: WorkspaceTerminalLaunchRequest(
                projectPath: "/tmp/devhaven",
                workspaceId: "workspace:test",
                tabId: "tab:test",
                paneId: "pane:test",
                surfaceId: "surface:test",
                terminalSessionId: "session:test"
            )
        )

        let start = Date(timeIntervalSince1970: 100)
        let cached = model.currentVisibleText(
            now: start,
            sampling: .preferCache,
            sampleVisibleText: { "echo first" }
        )
        let reused = model.currentVisibleText(
            now: start.addingTimeInterval(1),
            sampling: .preferCache,
            sampleVisibleText: { "echo second" }
        )
        let refreshed = model.currentVisibleText(
            now: start.addingTimeInterval(1),
            sampling: .forceRefresh,
            sampleVisibleText: { "echo second" }
        )
        let expired = model.currentVisibleText(
            now: start.addingTimeInterval(GhosttySurfaceHostModel.restoreVisibleTextCacheInterval + 1),
            sampling: .preferCache,
            sampleVisibleText: { "echo third" }
        )

        XCTAssertEqual(cached, "echo first")
        XCTAssertEqual(reused, "echo first")
        XCTAssertEqual(refreshed, "echo second")
        XCTAssertEqual(expired, "echo third")
    }
}
