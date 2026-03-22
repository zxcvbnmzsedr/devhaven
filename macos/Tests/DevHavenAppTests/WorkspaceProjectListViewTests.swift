import XCTest

final class WorkspaceProjectListViewTests: XCTestCase {
    func testProjectCardDoesNotRenderWorktreeCountBadge() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("ForEach(group.worktrees)"), "下方 worktree 列表仍应继续渲染")
        XCTAssertFalse(source.contains("group.worktrees.count"), "项目卡片不应再使用 group.worktrees.count 渲染数量徽标")
    }

    func testQuickTerminalGroupDoesNotRenderWorktreeActionButtons() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("if !group.rootProject.isQuickTerminal"),
            "quick terminal group 应显式跳过 worktree 操作按钮"
        )
    }


    func testAgentSummaryRenderingDeduplicatesLabelAndSummary() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("displayedAgentSummaryText"),
            "WorkspaceProjectListView 应提取 agent 摘要去重逻辑，避免 label 与 summary 完全重复时重复渲染"
        )
    }

    func testWorktreeRowsShowAgentLabelEvenWithoutSummary() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("displayedWorktreeAgentText"),
            "worktree 行应有独立的 agent 文案退回逻辑，保证没有 summary 时也能显示 label"
        )
    }

    func testWorktreeRowsRenderNotificationPopoverAndBellIcon() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("WorkspaceNotificationPopoverButton"), "worktree 行应复用通知 popover 入口")
        XCTAssertTrue(source.contains("bell.fill"), "有未读通知时应显示 bell.fill 图标")
    }

    private func sourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/WorkspaceProjectListView.swift")
    }
}
