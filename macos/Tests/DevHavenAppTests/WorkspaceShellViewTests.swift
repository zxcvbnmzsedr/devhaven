import XCTest

final class WorkspaceShellViewTests: XCTestCase {
    func testWorkspaceShellNoLongerOwnsProjectSidebarSplit() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertFalse(
            source.contains("WorkspaceProjectSidebarHostView("),
            "项目导航已经外置到 Workspace 根布局，WorkspaceShellView 不应重新直接承载项目导航宿主"
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

    func testWorkspaceShellNoLongerRoutesCommitToolWindowThroughBottomHost() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertFalse(source.contains("commitToolWindowContent"), "Commit 改为左侧独立工具窗后，WorkspaceShellView 不应继续提供 commit 底部路由")
        XCTAssertFalse(source.contains("WorkspaceCommitRootView("), "Commit 改为左侧独立工具窗后，WorkspaceShellView 不应继续直接挂载 Commit 根容器")
    }

    func testWorkspaceShellBottomToolWindowTapSetsFocusedAreaToBottomGitKind() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("setWorkspaceFocusedArea(.bottomToolWindow(.git))"), "点击底部 Git tool window 内容时应显式把 focused area 切到底部 Git")
    }

    func testWorkspaceShellHostsCommitSidePanelInTopAreaAboveBottomToolWindow() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("WorkspaceCommitSideToolWindowHostView(viewModel: viewModel)"), "Commit 侧边工具窗宿主应下沉到 WorkspaceShellView 的主内容层")
        XCTAssertTrue(source.contains("workspaceSideToolWindowState.isVisible"), "Shell 应基于 side tool window state 决定是否展示 Commit 侧边工具窗")
        XCTAssertTrue(source.contains("updateWorkspaceSideToolWindowWidth"), "Commit 侧边工具窗宽度拖拽应由 Shell 承接")
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
