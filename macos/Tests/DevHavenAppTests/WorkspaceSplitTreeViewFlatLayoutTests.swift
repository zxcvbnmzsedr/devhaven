import XCTest

final class WorkspaceSplitTreeViewFlatLayoutTests: XCTestCase {
    func testSplitTreeViewUsesFlatLeafFramesInsteadOfRecursivePaneHosts() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("root.leafFrames(in: canvasFrame)"),
            "分屏树应先把 leaf pane 扁平化成 frame 列表，再稳定渲染 pane host，避免旧 pane 跟着递归树换宿主"
        )
        XCTAssertTrue(
            source.contains("root.splitHandles(in: canvasFrame"),
            "分屏树应单独渲染 split handle overlay，而不是让 pane host 继续嵌套在递归 split 容器里"
        )
        XCTAssertFalse(
            source.contains("private struct SubtreeView"),
            "采用扁平 pane 布局后，不应继续通过递归 SubtreeView 创建 pane 宿主"
        )
        XCTAssertFalse(
            source.contains("WorkspaceSplitView("),
            "采用扁平 pane 布局后，WorkspaceSplitTreeView 不应再递归嵌套 WorkspaceSplitView 作为 pane 宿主容器"
        )
    }

    private func sourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/WorkspaceSplitTreeView.swift")
    }
}
