import XCTest

final class WorkspaceTabBarViewTests: XCTestCase {
    func testWorkspaceTabBarConsumesUnifiedPresentedTabItems() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("let tabs: [WorkspacePresentedTabItem]"), "WorkspaceTabBarView 应消费统一 presented tab item，而不是继续只认 WorkspaceTabState")
        XCTAssertTrue(source.contains("let onSelectTab: (WorkspacePresentedTabSelection) -> Void"), "tab bar 选中动作应改成统一 presented tab selection")
        XCTAssertTrue(source.contains("let onCloseTab: (WorkspacePresentedTabSelection) -> Void"), "tab bar 关闭动作也应统一覆盖 terminal/diff tab")
    }

    func testWorkspaceTabBarDisablesSplitButtonsWhenDiffTabIsSelected() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("let isDiffTabSelected"), "WorkspaceTabBarView 应显式计算当前是否为 diff tab 选中")
        XCTAssertTrue(source.contains("disabled: !canSplit || isDiffTabSelected"), "选中 diff tab 时，split 按钮必须禁用")
        XCTAssertTrue(source.contains("switch tab.selection"), "tab bar 渲染应显式区分 terminal/diff tab 的 selection 语义")
    }

    private func sourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/WorkspaceTabBarView.swift")
    }
}
