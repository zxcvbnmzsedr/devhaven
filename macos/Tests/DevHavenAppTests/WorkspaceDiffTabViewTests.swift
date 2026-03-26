import XCTest

final class WorkspaceDiffTabViewTests: XCTestCase {
    func testDiffTabViewUsesNavigationBarAndPaneHeaderSubcomponents() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("WorkspaceDiffNavigationBarView("), "Diff 标签页应把顶部导航壳拆到独立 navigation bar 组件")
        XCTAssertTrue(source.contains("WorkspaceDiffPaneHeaderView("), "Diff 标签页应把 pane 标题拆到独立 header 组件")
        XCTAssertFalse(source.contains("currentSubtitle"), "Diff 标签页不应继续自己拼 subtitle/helper")
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

        XCTAssertTrue(source.contains("patchViewerContent"), "WorkspaceDiffTabView 应把 patch viewer 抽成独立 helper")
        XCTAssertTrue(source.contains("compareEditorContent"), "WorkspaceDiffTabView 应新增真实 compare editor 分支")
        XCTAssertTrue(source.contains("mergeEditorContent"), "WorkspaceDiffTabView 应新增 conflicted 三路 merge editor 分支")
    }

    func testDiffTabViewUsesEditableTextHostInsteadOfOnlyReadOnlyPatchText() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("WorkspaceTextEditorView("), "compare/merge editor 应通过真实文本编辑宿主承接，而不是继续只渲染 Text")
        XCTAssertTrue(source.contains("saveEditableContent"), "Diff toolbar 应提供保存动作，把 LOCAL/result 写回文件")
        XCTAssertTrue(source.contains("applyMergeAction"), "merge editor 应提供 ours/theirs/both 等结果区动作")
    }

    func testDiffTabViewProvidesBlockLevelCompareAndMergeActionSections() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("compareBlocksSidebar"), "compare editor 应存在独立的 side rail，承接 hunk 级动作")
        XCTAssertTrue(source.contains("mergeConflictSidebar"), "merge editor 应存在独立的 side rail，承接块级 accept 动作")
        XCTAssertTrue(source.contains("document.blocks"), "compare editor 应消费 compare blocks，而不是只渲染纯文本 pane")
        XCTAssertTrue(source.contains("document.conflictBlocks"), "merge editor 应消费 conflict blocks，而不是只有整文件按钮")
    }

    func testDiffTabViewPassesHighlightsAndScrollSyncIntoTextEditors() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("highlights: pane.highlights"), "Diff 视图应把 Core 生成的 line highlights 传给文本编辑器")
        XCTAssertTrue(source.contains("inlineHighlights: pane.inlineHighlights"), "Diff 视图应把 Core 生成的字符级 highlights 继续传给文本编辑器")
        XCTAssertTrue(source.contains("scrollSyncState:"), "Diff 视图应把同步滚动状态桥接到文本编辑器")
    }

    func testDiffTabViewAllowsUntrackedBlocksToUseStageAction() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("document.mode == .untracked"), "Diff 视图应显式识别 untracked compare 模式")
        XCTAssertTrue(source.contains("Button(\"暂存此块\")"), "untracked compare 也应复用 block 级暂存动作入口")
    }

    func testDiffTabViewTracksSelectedBlockInsideSideRail() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("@State private var selectedCompareBlockID"), "compare side rail 应维护当前选中 block")
        XCTAssertTrue(source.contains("@State private var selectedMergeBlockID"), "merge side rail 应维护当前选中 block")
        XCTAssertTrue(source.contains("selectedCompareBlockID == block.id"), "compare side rail 应有选中态渲染")
        XCTAssertTrue(source.contains("selectedMergeBlockID == block.id"), "merge side rail 应有选中态渲染")
    }

    func testDiffTabViewIssuesScrollRequestWhenSideRailBlockTapped() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("@State private var editorScrollRequestState"), "Diff 视图应维护 editor scroll request 状态")
        XCTAssertTrue(source.contains("scrollCompareBlockIntoView"), "compare side rail 点击后应发出滚动请求")
        XCTAssertTrue(source.contains("scrollMergeBlockIntoView"), "merge side rail 点击后应发出滚动请求")
        XCTAssertTrue(source.contains("scrollRequestState: $editorScrollRequestState"), "editor 宿主应接收滚动请求绑定")
    }

    func testDiffTabViewProvidesIdeaLikeOverviewGutterForBlocks() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("compareOverviewGutter"), "compare editor 应提供更像 IDEA gutter 的 overview rail")
        XCTAssertTrue(source.contains("mergeOverviewGutter"), "merge editor 应提供更像 IDEA gutter 的 overview rail")
        XCTAssertTrue(source.contains("blockOverviewMarker"), "overview rail 应通过独立 marker helper 渲染 block 导航点")
        XCTAssertTrue(source.contains("GeometryReader"), "overview rail 应基于可用高度按比例布局 block marker")
    }

    private func sourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/WorkspaceDiffTabView.swift")
    }
}
