import XCTest
@testable import DevHavenApp
@testable import DevHavenCore

@MainActor
final class GhosttySurfaceHostModelSnapshotTests: XCTestCase {
    func testRestoreContextSeedsWorkingDirectoryTitleAndSnapshotFallback() {
        let request = WorkspaceTerminalLaunchRequest(
            projectPath: "/tmp/devhaven",
            workspaceId: "workspace:test",
            tabId: "tab:test",
            paneId: "pane:test",
            surfaceId: "surface:test",
            terminalSessionId: "session:test",
            workingDirectoryOverride: "/tmp/devhaven/subdir",
            restoreContext: WorkspaceTerminalRestoreContext(
                workingDirectory: "/tmp/devhaven/subdir",
                title: "恢复窗格",
                snapshotText: "git status\nOn branch main",
                agentSummary: "Claude 正在等待"
            )
        )

        let model = GhosttySurfaceHostModel(request: request)
        let snapshot = model.snapshotContext()

        XCTAssertEqual(model.surfaceWorkingDirectory, "/tmp/devhaven/subdir")
        XCTAssertEqual(model.surfaceTitle, "恢复窗格")
        XCTAssertEqual(snapshot.workingDirectory, "/tmp/devhaven/subdir")
        XCTAssertEqual(snapshot.title, "恢复窗格")
        XCTAssertEqual(snapshot.visibleText, "git status\nOn branch main")
        XCTAssertEqual(snapshot.agentSummary, "Claude 正在等待")
    }

    func testSnapshotContextPrefersLiveStateOverRestoreFallback() {
        let request = WorkspaceTerminalLaunchRequest(
            projectPath: "/tmp/devhaven",
            workspaceId: "workspace:test",
            tabId: "tab:test",
            paneId: "pane:test",
            surfaceId: "surface:test",
            terminalSessionId: "session:test",
            restoreContext: WorkspaceTerminalRestoreContext(
                workingDirectory: "/tmp/devhaven/old",
                title: "旧标题",
                snapshotText: "old text",
                agentSummary: nil
            )
        )
        let model = GhosttySurfaceHostModel(request: request)

        model.surfaceWorkingDirectory = "/tmp/devhaven/live"
        model.surfaceTitle = "实时标题"

        let snapshot = model.snapshotContext()
        XCTAssertEqual(snapshot.workingDirectory, "/tmp/devhaven/live")
        XCTAssertEqual(snapshot.title, "实时标题")
        XCTAssertEqual(snapshot.visibleText, "old text")
    }

    func testCodexDisplaySnapshotKeepsOnlyTrailingWindowWhenTrackingEnabled() {
        let request = WorkspaceTerminalLaunchRequest(
            projectPath: "/tmp/devhaven",
            workspaceId: "workspace:test",
            tabId: "tab:test",
            paneId: "pane:test",
            surfaceId: "surface:test",
            terminalSessionId: "session:test"
        )
        let model = GhosttySurfaceHostModel(request: request)
        model.setCodexDisplayTrackingEnabled(true)

        let longText = String(repeating: "0123456789", count: 600)
        model.updateCodexDisplaySnapshot(withVisibleText: longText, now: Date(timeIntervalSince1970: 123))

        let snapshot = try? XCTUnwrap(model.codexDisplaySnapshot())
        XCTAssertNotNil(snapshot)
        XCTAssertEqual(snapshot?.lastActivityAt, Date(timeIntervalSince1970: 123))
        XCTAssertEqual(snapshot?.recentTextWindow.count, GhosttySurfaceHostModel.codexDisplaySnapshotWindowLimit)
        XCTAssertTrue(snapshot?.recentTextWindow.hasSuffix(String(repeating: "0123456789", count: 20)) == true)
    }

    func testDisablingCodexDisplayTrackingClearsCachedSnapshot() {
        let request = WorkspaceTerminalLaunchRequest(
            projectPath: "/tmp/devhaven",
            workspaceId: "workspace:test",
            tabId: "tab:test",
            paneId: "pane:test",
            surfaceId: "surface:test",
            terminalSessionId: "session:test"
        )
        let model = GhosttySurfaceHostModel(request: request)
        model.setCodexDisplayTrackingEnabled(true)
        model.updateCodexDisplaySnapshot(
            withVisibleText: "OpenAI Codex\nWorking (13s • esc to interrupt)",
            now: Date(timeIntervalSince1970: 456)
        )

        XCTAssertNotNil(model.codexDisplaySnapshot())

        model.setCodexDisplayTrackingEnabled(false)

        XCTAssertNil(model.codexDisplaySnapshot())
    }
}
