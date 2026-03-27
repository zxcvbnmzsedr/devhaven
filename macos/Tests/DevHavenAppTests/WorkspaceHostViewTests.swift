import XCTest

final class WorkspaceHostViewTests: XCTestCase {
    func testWorkspaceHostConsumesPresentedTabsInsteadOfOnlyRawTerminalTabs() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("workspacePresentedTabs(for: project.path)"), "WorkspaceHostView 应从 ViewModel 读取统一 presented tabs，而不是只消费 workspace.tabs")
        XCTAssertTrue(source.contains("workspaceSelectedPresentedTab(for: project.path)"), "WorkspaceHostView 应读取当前 project 的 presented tab 选中态")
        XCTAssertTrue(source.contains("WorkspaceTabBarView("), "WorkspaceHostView 应继续通过统一 tab bar 宿主渲染顶部标签")
    }

    func testWorkspaceHostRoutesSelectedDiffTabAwayFromTerminalSplitTree() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("case let .diff(diffTabID)"), "WorkspaceHostView 应显式识别 diff tab 选中分支")
        XCTAssertTrue(source.contains("WorkspaceDiffTabView(viewModel:"), "WorkspaceHostView 在 diff tab 选中时应真正挂载 WorkspaceDiffTabView")
        XCTAssertFalse(source.contains("ForEach(workspace.tabs)"), "WorkspaceHostView 不应继续把 terminal tabs 当作唯一顶层内容来源")
    }

    func testWorkspaceHostBridgesDiffContentTapBackIntoDiffFocusedArea() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("setWorkspaceFocusedArea(.diffTab(diffTabID))"), "点击 diff 内容区时，WorkspaceHostView 应显式把 focused area 回写到当前 diff 标签页")
    }

    private func sourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/WorkspaceHostView.swift")
    }
}
