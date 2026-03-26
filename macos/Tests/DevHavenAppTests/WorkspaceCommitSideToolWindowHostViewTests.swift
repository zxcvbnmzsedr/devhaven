import XCTest

final class WorkspaceCommitSideToolWindowHostViewTests: XCTestCase {
    func testWorkspaceCommitSideHostRoutesCommitRootViewAndEmptyStates() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("WorkspaceCommitRootView("), "Commit 侧边工具窗宿主应挂载既有 Commit 根容器")
        XCTAssertTrue(source.contains("activeWorkspaceCommitViewModel"), "Commit 侧边工具窗宿主应消费 NativeAppViewModel 的 commit view model 真相源")
        XCTAssertTrue(source.contains("快速终端暂不支持 Commit 模式"), "Commit 侧边工具窗宿主应保留快速终端空状态")
        XCTAssertTrue(source.contains("当前项目不是 Git 仓库"), "Commit 侧边工具窗宿主应保留非 Git 项目空状态")
    }

    func testWorkspaceCommitSideHostSetsFocusedAreaToSideCommit() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("setWorkspaceFocusedArea(.sideToolWindow(.commit))"), "点击 Commit 侧边工具窗内容时应显式把 focused area 切到侧边 Commit")
    }

    func testWorkspaceCommitSideHostUsesSinglePreviewDiffActions() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("syncActiveWorkspaceCommitDiffPreviewIfNeeded("), "Commit 侧边宿主应支持只同步已打开的 preview，而不是每次选择都新建标签页")
        XCTAssertTrue(source.contains("openActiveWorkspaceCommitDiffPreview("), "Commit 侧边宿主应支持打开或聚焦单实例 preview")
        XCTAssertTrue(source.contains("allChanges: commitViewModel.changesSnapshot?.changes"), "Commit 侧边宿主应把当前 changes snapshot 传给 preview 打开链路，用于构造 request chain")
        XCTAssertFalse(source.contains("openActiveWorkspaceDiffTab("), "Commit 单实例 preview 落地后，宿主不应继续直接调用通用的 file-scoped diff 打开入口")
    }

    private func sourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/WorkspaceCommitSideToolWindowHostView.swift")
    }
}
