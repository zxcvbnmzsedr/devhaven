import XCTest

final class WorkspaceGitIdeaLogViewTests: XCTestCase {
    func testIdeaLogContainerBuildsToolbarTableBottomPaneAndDiffPreview() throws {
        let source = try String(contentsOf: sourceFileURL(named: "WorkspaceGitIdeaLogView.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("WorkspaceGitIdeaLogToolbarView("), "标准 IDEA Log 顶部应使用独立 toolbar 视图")
        XCTAssertTrue(source.contains("WorkspaceGitIdeaLogTableView("), "标准 IDEA Log 中间应使用独立 table 视图")
        XCTAssertTrue(source.contains("WorkspaceGitIdeaLogBottomPaneView("), "标准 IDEA Log 下半区应使用独立 bottom pane 视图")
        XCTAssertTrue(source.contains("WorkspaceGitIdeaLogDiffPreviewView("), "标准 IDEA Log 应包含独立 diff preview pane")
        XCTAssertGreaterThanOrEqual(source.components(separatedBy: "WorkspaceSplitView(").count - 1, 2, "标准 IDEA Log 应至少包含主区/底部区与 diff preview 两层 split")
    }

    func testIdeaLogToolbarProvidesStandardFiltersAndPreviewToggles() throws {
        let source = try String(contentsOf: sourceFileURL(named: "WorkspaceGitIdeaLogToolbarView.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("selectRevisionFilter"), "标准 IDEA Log toolbar 应提供 branch/revision filter")
        XCTAssertTrue(source.contains("selectAuthorFilter"), "标准 IDEA Log toolbar 应提供 author filter")
        XCTAssertTrue(source.contains("selectDateFilter"), "标准 IDEA Log toolbar 应提供 date filter")
        XCTAssertTrue(source.contains("updatePathFilterQuery"), "标准 IDEA Log toolbar 应提供 path filter")
        XCTAssertTrue(source.contains("toggleDetails"), "标准 IDEA Log toolbar 应提供详情区显隐开关")
        XCTAssertTrue(source.contains("toggleDiffPreview"), "标准 IDEA Log toolbar 应提供 diff preview 显隐开关")
    }

    func testIdeaLogTableUsesTableColumnsInsteadOfScrollList() throws {
        let source = try String(contentsOf: sourceFileURL(named: "WorkspaceGitIdeaLogTableView.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("Table("), "标准 IDEA Log 提交区应使用 macOS Table，而不是 ScrollView + LazyVStack")
        XCTAssertTrue(source.contains("WorkspaceGitLogColumn.defaultColumns"), "标准 IDEA Log table 应绑定显式列模型")
        XCTAssertTrue(source.contains("isCommitHighlightedOnCurrentBranch"), "标准 IDEA Log table 应支持 current branch highlight 语义")
        XCTAssertTrue(source.contains("WorkspaceGitCommitGraphView("), "标准 IDEA Log table 应使用独立 graph renderer，而不是继续直接显示 graphPrefix 文本")
        XCTAssertFalse(source.contains("Text(commit.graphPrefix"), "标准 IDEA Log table 不应继续使用字符假图谱")
        XCTAssertFalse(source.contains("frame(width: 28"), "标准 IDEA Log graph 区域宽度不应继续写死为 28pt")
        XCTAssertFalse(source.contains("graphLayout"), "标准 IDEA Log table 不应继续绑定旧 glyph graphLayout")
    }

    func testIdeaLogTableCapturesGraphWidthOutsidePerRowCellClosure() throws {
        let source = try String(contentsOf: sourceFileURL(named: "WorkspaceGitIdeaLogTableView.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("let graphWidth = viewModel.preferredGraphWidth"), "table 应在 body 顶层先读取一次 graphWidth，避免每个 row cell 重复触发 viewModel 热路径")
        XCTAssertFalse(source.contains("width: viewModel.preferredGraphWidth"), "graphWidth 不应继续在每个 row cell 里直接回读 viewModel")
    }

    func testIdeaLogGraphViewUsesCanvasRenderer() throws {
        let source = try String(contentsOf: sourceFileURL(named: "WorkspaceGitCommitGraphView.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("Canvas"), "标准 IDEA Log graph 应使用 Canvas 连续绘制")
        XCTAssertTrue(source.contains("WorkspaceGitCommitGraphVisibleRow"), "graph view 应消费 visible graph row，而不是旧的 graphPrefix/glyph layout")
        XCTAssertTrue(source.contains("edgeElements"), "graph view 应基于 print elements 绘制 edge，而不是旧 glyph 枚举")
    }

    func testIdeaLogGraphRendererUsesBranchPaletteInsteadOfSingleAccentStroke() throws {
        let source = try String(contentsOf: sourceFileURL(named: "WorkspaceGitCommitGraphView.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("branchColor"), "graph renderer 应根据 graph element 的 branch/color index 取色，而不是整张图只用一个 accent 颜色")
        XCTAssertTrue(source.contains("edge.colorIndex"), "edge 绘制应消费结构化 color index")
        XCTAssertTrue(source.contains("node.colorIndex"), "node 绘制应消费结构化 color index")
    }

    func testIdeaLogGraphRendererUsesAdjacentRowConnectionInsteadOfAnchorStitching() throws {
        let source = try String(contentsOf: sourceFileURL(named: "WorkspaceGitCommitGraphView.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("positionInCurrentRow"), "graph renderer 应基于当前 row position 连接线段")
        XCTAssertTrue(source.contains("positionInOtherRow"), "graph renderer 应基于相邻 row position 连接线段")
        XCTAssertFalse(source.contains("WorkspaceGitCommitGraphRowAnchor"), "graph renderer 不应继续依赖 top/middle/bottom anchor 拼接算法")
    }

    func testIdeaLogGraphRendererFillsTableRowHeightToAvoidBrokenVerticalLines() throws {
        let graphSource = try String(contentsOf: sourceFileURL(named: "WorkspaceGitCommitGraphView.swift"), encoding: .utf8)
        let tableSource = try String(contentsOf: sourceFileURL(named: "WorkspaceGitIdeaLogTableView.swift"), encoding: .utf8)

        XCTAssertTrue(graphSource.contains("static let rowHeight: CGFloat = 28"), "graph renderer 应把统一 rowHeight 提升到更接近 table 可见行盒的高度，减少上下留缝")
        XCTAssertTrue(
            tableSource.contains(".frame(height: WorkspaceGitCommitGraphView.rowHeight, alignment: .leading)"),
            "table subject cell 应与 graph 共用固定高度真相源，而不是继续只给一个 minHeight"
        )
        XCTAssertFalse(tableSource.contains(".padding(.vertical, 1)"), "标准 IDEA Log graph 行不应再保留额外垂直 padding，否则视觉上仍会断线")
        XCTAssertFalse(tableSource.contains("minHeight: WorkspaceGitCommitGraphView.rowHeight"), "subject cell 不应继续只设置 minHeight，否则选中背景与 graph 仍会悬在行中间")
    }

    func testIdeaLogSubjectCellCompensatesTableVerticalInset() throws {
        let source = try String(contentsOf: sourceFileURL(named: "WorkspaceGitIdeaLogTableView.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("verticalInsetCompensation"), "subject cell 应显式声明 Table cell 垂直 inset 补偿常量，避免 magic number 散落在布局链路中")
        XCTAssertTrue(
            source.contains(".padding(.vertical, -TableCellMetrics.verticalInsetCompensation)"),
            "subject cell 应对 Table 默认垂直 inset 做反向补偿，否则背景与 graph 仍会被额外顶出上下缝"
        )
    }

    func testIdeaLogGraphRendererOverdrawsRowBoundariesAndAlignsStrokeToPixels() throws {
        let source = try String(contentsOf: sourceFileURL(named: "WorkspaceGitCommitGraphView.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("static let verticalOverflow"), "graph renderer 应显式 overdraw row 上下边界，避免 Canvas 在 row 裁切处留下 seam")
        XCTAssertTrue(source.contains("pixelAligned"), "graph renderer 应将 graph x/y 位置收口到统一像素对齐 helper，避免线条发虚或看起来断续")
    }

    func testIdeaLogGraphRendererClipsEachPrintElementToCurrentRowViewportLikeIdeaPainter() throws {
        let source = try String(contentsOf: sourceFileURL(named: "WorkspaceGitCommitGraphView.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("visibleEndpoint"), "graph renderer 应像 IDEA painter 一样先算当前 row 视口内可见的 edge endpoint，而不是直接把整条 center-to-center 线段画满两整行")
        XCTAssertFalse(
            source.contains("height: Self.rowHeight + GraphVisualMetrics.verticalOverflow * 2 + Self.rowHeight"),
            "graph renderer 不应继续让当前 row 的 Canvas 跨两整行；否则 `.up/.down` 双向 segment 会在相邻 row 中重复整段绘制"
        )
    }

    func testIdeaLogBottomPaneSeparatesChangesAndDetails() throws {
        let source = try String(contentsOf: sourceFileURL(named: "WorkspaceGitIdeaLogBottomPaneView.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("WorkspaceGitIdeaLogChangesView("), "标准 IDEA Log 左下区域应为 changes browser")
        XCTAssertTrue(source.contains("WorkspaceGitIdeaLogDetailsView("), "标准 IDEA Log 右下区域应为 commit details")
        XCTAssertTrue(source.contains("direction: .horizontal"), "标准 IDEA Log 的 changes/details 区应使用横向 split")
    }

    private func sourceFileURL(named name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/\(name)")
    }
}
