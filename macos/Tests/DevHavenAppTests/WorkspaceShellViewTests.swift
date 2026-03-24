import XCTest

final class WorkspaceShellViewTests: XCTestCase {
    func testWorkspaceShellUsesResizableSplitViewForSidebar() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("WorkspaceSplitView("),
            "工作区壳层应改用可拖拽的分栏容器，否则左侧项目侧边栏无法调整宽度"
        )
    }

    func testWorkspaceShellDoesNotPinSidebarToFixedWidth() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertFalse(
            source.contains(".frame(width: 280)"),
            "工作区左侧侧边栏不应再被固定到 280pt，否则拖拽分隔线不会生效"
        )
    }

    func testWorkspaceShellReadsInitialSidebarWidthFromViewModelSettings() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("viewModel.workspaceSidebarWidth"),
            "工作区侧边栏初始宽度应从 ViewModel 的全局设置读取，而不是永远只用运行时默认值"
        )
    }

    func testWorkspaceShellPersistsSidebarWidthWhenDragEnds() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("onRatioChangeEnded"),
            "工作区侧边栏应在拖拽结束时提交持久化，而不是只更新本地状态"
        )
        XCTAssertTrue(
            source.contains("viewModel.updateWorkspaceSidebarWidth"),
            "工作区侧边栏拖拽结束后应把宽度写回全局设置"
        )
    }

    func testWorkspaceShellViewRefreshesCodexDisplayStateOnTimer() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("CodexAgentDisplayStateRefresher.refresh"), "WorkspaceShellView 应定期刷新 Codex 展示态")
        XCTAssertTrue(source.contains("Timer.publish"), "WorkspaceShellView 应以定时方式触发 Codex 展示态刷新")
        XCTAssertTrue(source.contains("codexDisplayRefreshState"), "WorkspaceShellView 应保留 Codex 展示态刷新所需的运行时观测状态")
    }

    func testWorkspaceShellStartsWorktreeCreationWithoutWaitingForFullProgressFlow() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("startCreateWorkspaceWorktree"),
            "WorkspaceShellView 应调用“先启动、后后台执行”的创建入口，让 worktree 对话框能立即退出并把全局进度弹窗露到最前面"
        )
    }

    func testWorkspaceShellProvidesFocusedOpenProjectPickerAction() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains(".focusedSceneValue(\\.openWorkspaceProjectPickerAction, openWorkspaceProjectPickerAction)"),
            "WorkspaceShellView 应向当前 scene 注入打开项目命令动作，供应用菜单快捷键路由"
        )
        XCTAssertTrue(
            source.contains("private var openWorkspaceProjectPickerAction: (() -> Void)?"),
            "WorkspaceShellView 应把打开项目命令封装为 focused action，而不是把命令状态散落到菜单层"
        )
    }

    private func sourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/WorkspaceShellView.swift")
    }
}
