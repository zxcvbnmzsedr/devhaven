import XCTest

final class WorkspaceDiffTabViewTests: XCTestCase {
    func testDiffTabViewUsesNavigationBarAndPaneHeaderSubcomponents() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)
        let twoSideSource = try String(contentsOf: twoSideViewerFileURL(), encoding: .utf8)
        let mergeSource = try String(contentsOf: mergeViewerFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("WorkspaceDiffNavigationBarView("), "Diff 标签页应把顶部导航壳拆到独立 navigation bar 组件")
        XCTAssertTrue(twoSideSource.contains("WorkspaceDiffPaneHeaderView("), "two-side viewer 应把 pane 标题拆到独立 header 组件")
        XCTAssertTrue(mergeSource.contains("WorkspaceDiffPaneHeaderView("), "merge viewer 应把 pane 标题拆到独立 header 组件")
        XCTAssertFalse(source.contains("currentSubtitle"), "Diff 标签页不应继续自己拼 subtitle/helper")
    }

    func testDiffTabViewHandlesLoadingLoadedAndErrorStates() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("switch viewModel.documentState.loadState"), "Diff 标签页必须按 document load state 路由不同内容")
        XCTAssertTrue(source.contains("ProgressView(\"正在加载 Diff…\""), "加载态应有明确中文文案")
        XCTAssertTrue(source.contains("case let .failed(message)"), "加载失败应显式落到独立错误分支")
        XCTAssertTrue(source.contains("case let .loaded(document)"), "加载成功应显式落到 loaded 分支")
    }

    func testDiffTabViewRoutesToPatchTwoSideAndMergeViewerSubcomponents() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("WorkspaceDiffPatchViewerView("), "Diff 标签页应把 patch viewer 路由到独立子组件")
        XCTAssertTrue(source.contains("WorkspaceDiffTwoSideViewerView("), "Diff 标签页应把 two-side compare 路由到独立子组件")
        XCTAssertTrue(source.contains("WorkspaceDiffMergeViewerView("), "Diff 标签页应把 merge viewer 路由到独立子组件")
    }

    func testDiffTabViewUsesEditableTextHostInsteadOfOnlyReadOnlyPatchText() throws {
        let twoSideSource = try String(contentsOf: twoSideViewerFileURL(), encoding: .utf8)
        let mergeSource = try String(contentsOf: mergeViewerFileURL(), encoding: .utf8)

        XCTAssertTrue(twoSideSource.contains("WorkspaceTextEditorView("), "two-side viewer 应通过真实文本编辑宿主承接 compare editor")
        XCTAssertTrue(mergeSource.contains("WorkspaceTextEditorView("), "merge viewer 应通过真实文本编辑宿主承接 merge editor")
        XCTAssertTrue(mergeSource.contains("applyMergeAction"), "merge viewer 应提供 ours/theirs/both 等结果区动作")
    }

    func testDiffTabViewRoutesCompareUnifiedModeThroughPatchViewer() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("if effectiveViewerMode == .unified"), "Diff 标签页应根据有效 viewer mode 决定 compare 文档是否切到 unified 呈现")
        XCTAssertTrue(source.contains("unifiedPatchDocument(for: compareDocument)"), "compare 文档切到统一模式时应生成 unified patch document")
        XCTAssertTrue(source.contains("viewerMode: .unified"), "compare unified 路由到 patch viewer 时应显式以 unified 模式渲染")
    }

    func testDiffTabViewKeepsMergeInSideBySideAndHidesUnsupportedUnifiedToggle() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("case .loaded(.merge):"), "Diff 标签页应显式识别 merge 文档的 viewer mode 支持边界")
        XCTAssertTrue(source.contains("return [.sideBySide]"), "merge 文档当前只应暴露 side-by-side 模式，避免继续显示无效 unified 开关")
        XCTAssertTrue(source.contains("get: { effectiveViewerMode }"), "顶栏 picker 应消费有效 viewer mode，而不是无条件绑定底层 runtime 值")
    }

    func testDiffTabViewProvidesBlockLevelCompareAndMergeActionSections() throws {
        let twoSideSource = try String(contentsOf: twoSideViewerFileURL(), encoding: .utf8)
        let mergeSource = try String(contentsOf: mergeViewerFileURL(), encoding: .utf8)

        XCTAssertFalse(twoSideSource.contains("compareBlocksSidebar"), "用户已明确不要 Diff Blocks 栏，compare editor 不应继续保留独立 side rail")
        XCTAssertFalse(twoSideSource.contains("Text(\"Diff Blocks\")"), "compare editor 不应继续显示 Diff Blocks 栏标题")
        XCTAssertTrue(mergeSource.contains("mergeConflictSidebar"), "merge editor 应存在独立的 side rail，承接块级 accept 动作")
        XCTAssertTrue(twoSideSource.contains("document.blocks"), "compare editor 应消费 compare blocks，而不是只渲染纯文本 pane")
        XCTAssertTrue(mergeSource.contains("document.conflictBlocks"), "merge editor 应消费 conflict blocks，而不是只有整文件按钮")
    }

    func testDiffTabViewKeepsCompareOverviewGutterAfterRemovingDiffBlocksSidebar() throws {
        let source = try String(contentsOf: twoSideViewerFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("compareOverviewGutter"), "删除 Diff Blocks 栏后，compare overview gutter 仍应保留")
        XCTAssertTrue(source.contains("blockOverviewMarker("), "删除侧栏后仍应通过 overview marker 承接块定位")
        XCTAssertFalse(source.contains("Button(\"暂存此块\")"), "删除 Diff Blocks 栏后，不应继续保留 compare 侧栏里的块级按钮")
    }

    func testTwoSideAndMergeViewerKeepSideRailAndOverviewSyncedWithCurrentDifference() throws {
        let twoSideSource = try String(contentsOf: twoSideViewerFileURL(), encoding: .utf8)
        let mergeSource = try String(contentsOf: mergeViewerFileURL(), encoding: .utf8)

        XCTAssertTrue(twoSideSource.contains("@State private var selectedCompareBlockID"), "two-side viewer 应维护当前选中 compare block")
        XCTAssertTrue(twoSideSource.contains("onChange(of: selectedDifference)"), "two-side viewer 应监听 processor selected difference")
        XCTAssertTrue(twoSideSource.contains("WorkspaceTextEditorScrollRequestKind.selectedDifference"), "two-side viewer 应发出 selected difference 滚动请求")
        XCTAssertTrue(twoSideSource.contains("compareOverviewGutter"), "two-side viewer 应继续承接 compare overview gutter")

        XCTAssertTrue(mergeSource.contains("@State private var selectedMergeBlockID"), "merge viewer 应维护当前选中 conflict block")
        XCTAssertTrue(mergeSource.contains("onChange(of: selectedDifference)"), "merge viewer 应监听 processor selected difference")
        XCTAssertTrue(mergeSource.contains("WorkspaceTextEditorScrollRequestKind.selectedDifference"), "merge viewer 应发出 selected difference 滚动请求")
        XCTAssertTrue(mergeSource.contains("mergeOverviewGutter"), "merge viewer 应继续承接 merge overview gutter")
    }

    private func sourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/WorkspaceDiffTabView.swift")
    }

    private func twoSideViewerFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/WorkspaceDiffTwoSideViewerView.swift")
    }

    private func mergeViewerFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/WorkspaceDiffMergeViewerView.swift")
    }
}
