import XCTest

final class WorkspaceShellViewGitModeTests: XCTestCase {
    func testWorkspaceShellViewIntegratesTerminalAndGitPrimaryModes() throws {
        let source = try String(contentsOf: workspaceShellSourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("WorkspaceModeSwitcherView(selection: $viewModel.workspacePrimaryMode)"),
            "WorkspaceShellView 应接入一级模式切换器，支持 Terminal/Git 模式切换"
        )
        XCTAssertTrue(
            source.contains("switch viewModel.workspacePrimaryMode"),
            "WorkspaceShellView 应按一级模式在 Terminal/Git 内容之间切换"
        )
    }

    func testWorkspaceShellViewGatesTerminalFocusedSearchActionsInGitMode() throws {
        let source = try String(contentsOf: workspaceShellSourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("guard viewModel.workspacePrimaryMode == .terminal else {"),
            "Git 模式下应禁用终端 focused search action，避免菜单命令误落到 terminal pane"
        )
    }

    func testWorkspaceShellViewProvidesQuickTerminalGitModeEmptyState() throws {
        let source = try String(contentsOf: workspaceShellSourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("快速终端暂不支持 Git 模式"),
            "Quick Terminal 进入 Git mode 时应提供明确空状态提示"
        )
    }

    func testWorkspaceShellViewProvidesNonGitProjectGitModeEmptyState() throws {
        let source = try String(contentsOf: workspaceShellSourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("当前项目不是 Git 仓库"),
            "非 Git 项目进入 Git mode 时应提供空状态提示"
        )
    }

    func testWorkspaceShellViewRoutesGitModeIntoWorkspaceGitRootView() throws {
        let source = try String(contentsOf: workspaceShellSourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("WorkspaceGitRootView(viewModel: gitViewModel)"),
            "WorkspaceShellView 应把真实 Git UI 外提到独立 WorkspaceGitRootView，而不是继续把 log/detail 内容堆在 shell 层"
        )
    }

    func testWorkspaceModeSwitcherViewProvidesTerminalAndGitOptions() throws {
        let source = try String(contentsOf: workspaceModeSwitcherSourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("WorkspacePrimaryMode.allCases"))
        XCTAssertTrue(source.contains("selection = mode"))
        XCTAssertTrue(source.contains("Text(mode.title)"))
    }

    private func workspaceShellSourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/WorkspaceShellView.swift")
    }

    private func workspaceModeSwitcherSourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/WorkspaceModeSwitcherView.swift")
    }
}
