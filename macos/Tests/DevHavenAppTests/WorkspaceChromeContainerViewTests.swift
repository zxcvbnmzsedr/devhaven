import XCTest

final class WorkspaceChromeContainerViewTests: XCTestCase {
    func testWorkspaceChromeContainerHostsToolWindowStripeInsideChromeInsteadOfShellBottomBar() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertFalse(source.contains("private var topBar"), "Workspace chrome 不应回退到旧顶部栏结构")
        XCTAssertFalse(source.contains("private var leftRail"), "迁移为 bottom tool window 后不应继续保留 leftRail")
        XCTAssertFalse(source.contains("private var rightRail"), "Workspace chrome 不应回退到旧右侧辅助栏结构")
        XCTAssertFalse(source.contains("WorkspaceModeSwitcherView("), "Chrome 容器不应继续承载模式切换器")
        XCTAssertTrue(source.contains("HStack(spacing: 0)"), "Chrome 容器应改为 `stripe | Commit 侧边工具窗 | 主内容区` 结构")
        XCTAssertTrue(source.contains("workspaceToolWindowStripe"), "Chrome 容器应在内部提供 tool window stripe")
        XCTAssertTrue(source.contains("toolWindowStripeButton(kind: .commit)"), "Stripe 应提供独立 Commit 工具窗入口")
        XCTAssertTrue(source.contains("toolWindowStripeButton(kind: .git)"), "Stripe 应保留 Git 工具窗入口")
        XCTAssertTrue(source.contains("toggleWorkspaceToolWindow(kind)"), "Stripe 按钮 action 应使用传入 kind，避免假泛化硬编码")
        XCTAssertTrue(source.contains("Image(systemName: kind.systemImage)"), "Stripe 按钮应为 icon-only")
    }

    func testWorkspaceChromeContainerNoLongerHostsCommitSidePanelBesideWholeShell() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertFalse(source.contains("WorkspaceCommitSideToolWindowHostView(viewModel: viewModel)"), "Commit 侧边工具窗不应挂在整个 Shell 左边，否则会落到底部 tools 面板左侧")
        XCTAssertFalse(source.contains("updateWorkspaceSideToolWindowWidth"), "Commit 侧边工具窗宽度拖拽不应由 Chrome 容器承接")
    }

    func testWorkspaceChromeContainerPinsCommitAndGitStripeButtonsToBottom() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("Spacer(minLength: 0)\n            toolWindowStripeButton(kind: .commit)\n            toolWindowStripeButton(kind: .git)"),
            "Commit/Git 图标应由上方 Spacer 挤压到 stripe 底部，且保持 Commit 与 Git 并列"
        )
    }

    func testWorkspaceChromeContainerKeepsNoOuterPaddingAfterRemovingLegacyRail() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertFalse(source.contains(".padding(10)"), "用户要求工作区 chrome 不要再有外边距")
    }

    func testWorkspaceChromeContainerNoLongerBindsPrimaryMode() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertFalse(source.contains("workspacePrimaryMode"), "Chrome 容器不应再绑定旧的 primary mode 真相源")
        XCTAssertFalse(source.contains("workspaceToolWindowState"), "Commit 已迁到左侧独立工具窗后，Chrome 容器不应继续依赖单一 tool window state")
    }

    func testWorkspaceChromeContainerRemovesTopBarProjectIdentityAndRightRailActions() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertFalse(source.contains("viewModel.activeWorkspaceProject"), "删除顶部内容后，不应再在 chrome 容器里展示 active project 标题/路径")
        XCTAssertFalse(source.contains("revealSettings"), "删除右侧内容后，不应再在 chrome 容器里保留设置入口按钮")
        XCTAssertFalse(source.contains("revealDashboard"), "删除右侧内容后，不应再在 chrome 容器里保留仪表盘入口按钮")
        XCTAssertFalse(source.contains("openWorkspaceInTerminal"), "删除右侧内容后，不应再在 chrome 容器里保留系统终端按钮")
    }

    private func sourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/WorkspaceChromeContainerView.swift")
    }
}
