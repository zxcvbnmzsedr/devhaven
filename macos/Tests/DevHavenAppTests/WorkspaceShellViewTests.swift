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

    func testWorkspaceShellViewUsesEventDrivenCodexPresentationCoordinator() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("CodexAgentPresentationCoordinator"), "WorkspaceShellView 应通过独立 coordinator 收口 Codex 展示态")
        XCTAssertTrue(source.contains("syncCodexPresentationCoordinator()"), "WorkspaceShellView 应在 workspace/runtime 边界变化时同步 coordinator")
        XCTAssertTrue(source.contains("viewModel.codexDisplayCandidates()"), "WorkspaceShellView 应在 agent signal 候选集合变化时重同步展示态 coordinator")
        XCTAssertFalse(source.contains("Timer.publish(every: 1"), "WorkspaceShellView 不应继续通过 1 秒定时器轮询 Codex 展示态")
        XCTAssertFalse(source.contains("CodexAgentDisplayStateRefresher.refresh"), "WorkspaceShellView 不应直接在 body 链路里调用 refresher.refresh")
        XCTAssertFalse(source.contains("currentVisibleText()"), "WorkspaceShellView 的 Codex 展示态链路不应直接读取当前可见全文")
    }

    func testWorkspaceProjectSidebarHostStartsWorktreeCreationWithoutWaitingForFullProgressFlow() throws {
        let source = try String(contentsOf: workspaceProjectSidebarHostFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("startCreateWorkspaceWorktree"),
            "外层项目导航宿主应调用“先启动、后后台执行”的创建入口，让 worktree 对话框能立即退出并把全局进度弹窗露到最前面"
        )
    }

    func testWorkspaceProjectSidebarHostProvidesFocusedOpenProjectPickerAction() throws {
        let source = try String(contentsOf: workspaceProjectSidebarHostFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains(".focusedSceneValue(\\.openWorkspaceProjectPickerAction, openWorkspaceProjectPickerAction)"),
            "WorkspaceProjectSidebarHostView 应向当前 scene 注入打开项目命令动作，供应用菜单快捷键路由"
        )
        XCTAssertTrue(
            source.contains("private var openWorkspaceProjectPickerAction: (() -> Void)?"),
            "WorkspaceProjectSidebarHostView 应把打开项目命令封装为 focused action，而不是把命令状态散落到菜单层"
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
