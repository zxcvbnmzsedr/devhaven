import XCTest

final class WorkspaceCommitRootViewTests: XCTestCase {
    func testWorkspaceCommitRootViewComposesChangesBrowserDiffPreviewAndCommitPanel() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("WorkspaceCommitChangesBrowserView("), "Commit 根容器应包含 changes browser 子视图")
        XCTAssertTrue(source.contains("WorkspaceCommitDiffPreviewView("), "Commit 根容器应包含 diff preview 子视图")
        XCTAssertTrue(source.contains("WorkspaceCommitPanelView("), "Commit 根容器应包含 commit panel 子视图")
    }

    func testWorkspaceCommitRootViewRefreshesSnapshotOnAppear() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("onAppear"), "Commit 根容器应在进入时触发初始化动作")
        XCTAssertTrue(source.contains("refreshChangesSnapshot()"), "Commit 根容器应在进入时刷新 changes snapshot")
    }

    private func sourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/WorkspaceCommitRootView.swift")
    }
}
