import XCTest

final class WorkspaceShellViewTests: XCTestCase {
    func testWorkspaceShellNoLongerOwnsProjectSidebarSplit() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertFalse(
            source.contains("WorkspaceSplitView(\n                direction: .horizontal"),
            "项目导航已经外置到 Workspace 根布局，WorkspaceShellView 不应再直接持有横向 split 容器"
        )
        XCTAssertFalse(
            source.contains("WorkspaceProjectListView("),
            "项目列表应位于 Workspace 外层导航，而不是继续直接挂在 WorkspaceShellView 里"
        )
    }

    func testWorkspaceShellViewRefreshesCodexDisplayStateOnTimer() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("CodexAgentDisplayStateRefresher.refresh"), "WorkspaceShellView 应定期刷新 Codex 展示态")
        XCTAssertTrue(source.contains("Timer.publish"), "WorkspaceShellView 应以定时方式触发 Codex 展示态刷新")
        XCTAssertTrue(source.contains("codexDisplayRefreshState"), "WorkspaceShellView 应保留 Codex 展示态刷新所需的运行时观测状态")
    }

    func testWorkspaceProjectSidebarHostStartsWorktreeCreationWithoutWaitingForFullProgressFlow() throws {
        let source = try String(contentsOf: workspaceProjectSidebarHostFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("startCreateWorkspaceWorktree"),
            "外层项目导航宿主应调用“先启动、后后台执行”的创建入口，让 worktree 对话框能立即退出并把全局进度弹窗露到最前面"
        )
    }

    func testWorkspaceShellRoutesCommitToolWindowKindToDedicatedCommitRootView() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("commitToolWindowContent"), "WorkspaceShellView 应提供独立 commit tool window 内容路由")
        XCTAssertTrue(source.contains("WorkspaceCommitRootView("), "activeKind == .commit 时应挂载 WorkspaceCommitRootView")
        XCTAssertTrue(source.contains("activeWorkspaceCommitViewModel"), "commit 路由应消费 NativeAppViewModel 的 commit view model 真相源")
    }

    func testWorkspaceShellCommitToolWindowTapSetsFocusedAreaToCommitKind() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("setWorkspaceFocusedArea(.toolWindow(.commit))"), "点击 commit tool window 内容时应显式把 focused area 切到 commit")
    }

    private func sourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/WorkspaceShellView.swift")
    }

    private func workspaceProjectSidebarHostFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/WorkspaceProjectSidebarHostView.swift")
    }
}
