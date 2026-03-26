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
        XCTAssertTrue(source.contains("diffTabPlaceholderContent"), "在真正 viewer 落地前，WorkspaceHostView 至少应有独立 diff host 占位分支")
        XCTAssertFalse(source.contains("ForEach(workspace.tabs)"), "WorkspaceHostView 不应继续把 terminal tabs 当作唯一顶层内容来源")
    }

    private func sourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/WorkspaceHostView.swift")
    }
}
