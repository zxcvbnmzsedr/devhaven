import XCTest

final class WorkspaceShellViewGitModeTests: XCTestCase {
    func testWorkspaceShellViewReplacesPrimaryModeSwitchWithTerminalAndToolWindowRuntimeState() throws {
        let source = try String(contentsOf: workspaceShellSourceFileURL(), encoding: .utf8)

        XCTAssertFalse(
            source.contains("switch viewModel.workspacePrimaryMode"),
            "WorkspaceShellView 不应继续按 workspacePrimaryMode 做 terminal/git 二选一"
        )
        XCTAssertTrue(source.contains("terminalModeContent"), "WorkspaceShellView 应保留 terminal 主区内容")
        XCTAssertTrue(source.contains("bottomToolWindowHost"), "WorkspaceShellView 应包含 bottom tool window host 结构锚点")
        XCTAssertFalse(source.contains("bottomToolWindowBar"), "Git 入口迁移到 chrome stripe 后，Shell 不应继续保留底部按钮栏")
        XCTAssertTrue(source.contains("workspaceToolWindowState"), "WorkspaceShellView 应消费 tool window runtime state")
    }

    func testWorkspaceShellViewRoutesGitThroughBottomToolWindowInsteadOfPrimaryModeCase() throws {
        let source = try String(contentsOf: workspaceShellSourceFileURL(), encoding: .utf8)

        XCTAssertFalse(source.contains("case .git"), "WorkspaceShellView 不应再通过 primary mode case 路由 Git")
        XCTAssertTrue(source.contains("workspaceToolWindowState"), "WorkspaceShellView 应通过 tool window state 决定底部内容路由")
        XCTAssertTrue(source.contains("activeKind"), "WorkspaceShellView 应读取 active tool window kind")
        XCTAssertTrue(source.contains(".git"), "WorkspaceShellView 应识别 Git 作为 tool window kind")
        XCTAssertTrue(source.contains("WorkspaceGitRootView("), "Git tool window 仍应挂载独立 WorkspaceGitRootView")
    }

    func testWorkspaceShellViewGatesTerminalFocusedSearchActionsByFocusedAreaNotPrimaryMode() throws {
        let source = try String(contentsOf: workspaceShellSourceFileURL(), encoding: .utf8)

        XCTAssertFalse(source.contains("guard viewModel.workspacePrimaryMode == .terminal else {"))
        XCTAssertTrue(source.contains("workspaceFocusedArea"), "WorkspaceShellView 应以 focused area 做 terminal 命令守门")
        XCTAssertTrue(source.contains(".terminal"), "WorkspaceShellView 应显式识别 terminal focused area")
    }

    func testWorkspaceShellViewProvidesQuickTerminalGitToolWindowEmptyState() throws {
        let source = try String(contentsOf: workspaceShellSourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("快速终端暂不支持 Git 模式"))
    }

    func testWorkspaceShellViewProvidesNonGitProjectGitToolWindowEmptyState() throws {
        let source = try String(contentsOf: workspaceShellSourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("当前项目不是 Git 仓库"),
            "Git tool window 在非 Git 场景应提供明确空状态提示"
        )
    }

    func testWorkspaceShellViewUsesResizableVerticalSplitForBottomToolWindowHeight() throws {
        let source = try String(contentsOf: workspaceShellSourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("WorkspaceSplitView("), "bottom tool window 应通过可拖拽 split 接入，而不是固定 frame 高度")
        XCTAssertTrue(source.contains("direction: .vertical"), "bottom tool window 与 terminal 主区应使用纵向 split")
        XCTAssertTrue(source.contains("updateWorkspaceToolWindowHeight"), "拖拽 bottom tool window 时应写回 tool window 高度真相源")
        XCTAssertTrue(source.contains("toolWindowSplitRatio"), "WorkspaceShellView 应显式根据高度真相源换算 split ratio")
        XCTAssertFalse(
            source.contains(".frame(height: CGFloat(viewModel.workspaceToolWindowState.height))"),
            "bottom tool window 不应继续只靠固定 frame(height:) 展示，否则无法拖拽改高度"
        )
    }

    private func workspaceShellSourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/WorkspaceShellView.swift")
    }
}
