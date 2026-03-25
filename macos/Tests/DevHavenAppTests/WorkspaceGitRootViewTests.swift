import XCTest

final class WorkspaceGitRootViewTests: XCTestCase {
    func testWorkspaceGitRootViewRoutesLogSectionIntoDedicatedIdeaLogContainer() throws {
        let source = try String(contentsOf: sourceFileURL(named: "WorkspaceGitRootView.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("WorkspaceGitIdeaLogView("), "标准 IDEA Log 应由独立容器承接，而不是继续复用旧的 list/detail/split 拼装")
        XCTAssertTrue(source.contains("case .log"), "Git Root 容器应在 Log 顶层 tab 下切换到标准 IDEA Log 实现")
    }

    func testWorkspaceGitRootViewKeepsSidebarOutsideLogOnly() throws {
        let source = try String(contentsOf: sourceFileURL(named: "WorkspaceGitRootView.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("WorkspaceGitSidebarView("), "非 `.log` section 仍应保留现有 sidebar/worktree selector")
        XCTAssertFalse(source.contains("showsExecutionWorktreeSelector: viewModel.section != .log"), "标准 IDEA Log 不应再通过 sidebar 控制隐藏 execution selector；`.log` 应完全脱离旧 sidebar")
    }

    func testWorkspaceGitRootViewStillRoutesOtherSectionsToDedicatedViews() throws {
        let source = try String(contentsOf: sourceFileURL(named: "WorkspaceGitRootView.swift"), encoding: .utf8)

        XCTAssertFalse(source.contains("WorkspaceGitChangesView("), "Git tool window 不应继续承载 Changes 视图")
        XCTAssertFalse(source.contains("case .changes"), "Git Root 容器 section switch 不应继续处理 `.changes`")
        XCTAssertTrue(source.contains("WorkspaceGitBranchesView("), "Branches section 仍应保留独立视图")
        XCTAssertTrue(source.contains("WorkspaceGitOperationsView("), "Operations section 仍应保留独立视图")
    }


    func testWorkspaceGitRootViewProvidesIdeaStyleTopTabsAndConsoleRoute() throws {
        let source = try String(contentsOf: sourceFileURL(named: "WorkspaceGitRootView.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("selectedTopLevelTab"), "Git Root 容器应显式维护顶层 Log / Console 选择状态")
        XCTAssertTrue(source.contains("gitTopTabStrip"), "Git Root 容器应提供独立的 IDEA 风格顶层区域")
        XCTAssertTrue(source.contains("gitToolWindowTitle"), "左上角 Git 应作为不可点击标题，而不是等权 tab")
        XCTAssertFalse(source.contains("topTabButton(.git"), "Git 不应继续作为可点击顶层按钮")
        XCTAssertTrue(source.contains("topTabButton(.log"), "顶层区域应包含 Log 入口")
        XCTAssertTrue(source.contains("topTabButton(.console"), "顶层区域应包含 Console 入口")
        XCTAssertTrue(source.contains("WorkspaceGitConsoleView("), "Git Root 容器应提供 Console 占位路由，先对齐 IDEA 顶层结构")
    }

    private func sourceFileURL(named name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/\(name)")
    }
}
