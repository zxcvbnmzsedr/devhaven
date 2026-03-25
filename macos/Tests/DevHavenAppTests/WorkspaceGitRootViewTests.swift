import XCTest

final class WorkspaceGitRootViewTests: XCTestCase {
    func testWorkspaceGitRootViewRoutesLogSectionIntoDedicatedIdeaLogContainer() throws {
        let source = try String(contentsOf: sourceFileURL(named: "WorkspaceGitRootView.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("WorkspaceGitIdeaLogView("), "标准 IDEA Log 应由独立容器承接，而不是继续复用旧的 list/detail/split 拼装")
        XCTAssertTrue(source.contains("if viewModel.section == .log"), "Git Root 容器应在 `.log` 时切换到标准 IDEA Log 实现")
    }

    func testWorkspaceGitRootViewKeepsSidebarOutsideLogOnly() throws {
        let source = try String(contentsOf: sourceFileURL(named: "WorkspaceGitRootView.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("WorkspaceGitSidebarView("), "非 `.log` section 仍应保留现有 sidebar/worktree selector")
        XCTAssertFalse(source.contains("showsExecutionWorktreeSelector: viewModel.section != .log"), "标准 IDEA Log 不应再通过 sidebar 控制隐藏 execution selector；`.log` 应完全脱离旧 sidebar")
    }

    func testWorkspaceGitRootViewStillRoutesOtherSectionsToDedicatedViews() throws {
        let source = try String(contentsOf: sourceFileURL(named: "WorkspaceGitRootView.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("WorkspaceGitChangesView("), "Changes section 仍应保留独立视图")
        XCTAssertTrue(source.contains("WorkspaceGitBranchesView("), "Branches section 仍应保留独立视图")
        XCTAssertTrue(source.contains("WorkspaceGitOperationsView("), "Operations section 仍应保留独立视图")
    }

    private func sourceFileURL(named name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/\(name)")
    }
}
