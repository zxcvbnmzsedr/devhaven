import XCTest

final class WorkspaceProjectListViewTests: XCTestCase {
    func testProjectCardDoesNotRenderWorktreeCountBadge() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("ForEach(group.worktrees)"), "下方 worktree 列表仍应继续渲染")
        XCTAssertFalse(source.contains("group.worktrees.count"), "项目卡片不应再使用 group.worktrees.count 渲染数量徽标")
    }

    private func sourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/WorkspaceProjectListView.swift")
    }
}
