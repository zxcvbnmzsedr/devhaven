import XCTest

final class WorkspaceDiffTabViewTests: XCTestCase {
    func testDiffTabViewProvidesToolbarAndViewerModeSwitcher() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("diffToolbar"), "WorkspaceDiffTabView 应通过独立 toolbar 承接标题和操作入口")
        XCTAssertTrue(source.contains("Picker(\"查看模式\""), "Diff 标签页应提供 side-by-side / unified 模式切换")
        XCTAssertTrue(source.contains("WorkspaceDiffViewerMode.sideBySide"), "viewer mode 切换必须显式包含 side-by-side")
        XCTAssertTrue(source.contains("WorkspaceDiffViewerMode.unified"), "viewer mode 切换必须显式包含 unified")
        XCTAssertTrue(source.contains("viewModel.updateViewerMode"), "切换模式时应驱动 WorkspaceDiffTabViewModel，而不是本地复制状态")
    }

    func testDiffTabViewHandlesLoadingLoadedAndErrorStates() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("switch viewModel.documentState.loadState"), "Diff 标签页必须按 document load state 路由不同内容")
        XCTAssertTrue(source.contains("ProgressView(\"正在加载 Diff…\""), "加载态应有明确中文文案")
        XCTAssertTrue(source.contains("case let .failed(message)"), "加载失败应显式落到独立错误分支")
        XCTAssertTrue(source.contains("case let .loaded(document)"), "加载成功应显式落到 loaded 分支")
    }

    func testDiffTabViewSupportsSideBySideAndUnifiedContentLayouts() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("sideBySideDiffContent"), "WorkspaceDiffTabView 应拆出 side-by-side 内容 helper")
        XCTAssertTrue(source.contains("unifiedDiffContent"), "WorkspaceDiffTabView 应拆出 unified 内容 helper")
        XCTAssertTrue(source.contains("document.kind"), "Diff 标签页应根据 parsed document kind 处理 text/empty/binary/unsupported")
    }

    private func sourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/WorkspaceDiffTabView.swift")
    }
}
