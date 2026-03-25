import XCTest

final class WorkspaceGitIdeaLogViewTests: XCTestCase {
    func testIdeaLogContainerBuildsToolbarTableAndRightSidebar() throws {
        let source = try String(contentsOf: sourceFileURL(named: "WorkspaceGitIdeaLogView.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("WorkspaceGitIdeaLogToolbarView("), "标准 IDEA Log 顶部应使用独立 toolbar 视图")
        XCTAssertTrue(source.contains("WorkspaceGitIdeaLogBranchesPanelView("), "标准 IDEA Log 左侧应挂载独立 branches panel")
        XCTAssertTrue(source.contains("branchesControlStrip"), "标准 IDEA Log 左侧应保留可展开 / 可收起的 control strip")
        XCTAssertTrue(source.contains("isBranchesPanelVisible"), "标准 IDEA Log 应维护 branches panel 的展开态")
        XCTAssertTrue(source.contains("WorkspaceGitIdeaLogTableView("), "标准 IDEA Log 中间应使用独立 table 视图")
        XCTAssertTrue(source.contains("WorkspaceGitIdeaLogRightSidebarView("), "标准 IDEA Log 最右侧应挂载独立信息栏")
        XCTAssertFalse(source.contains("WorkspaceGitIdeaLogBottomPaneView("), "标准 IDEA Log 主链不应再保留错误的底部 changes/details pane")
        XCTAssertFalse(source.contains("WorkspaceGitIdeaLogDiffPreviewView("), "标准 IDEA Log 主链不应继续保留错误的 diff preview")
        XCTAssertTrue(source.contains("direction: .horizontal"), "标准 IDEA Log 中间 table 与右侧信息栏应使用横向 split")
    }


    func testIdeaLogMainFrameOwnsToolbarInsteadOfPageLevelHeader() throws {
        let source = try String(contentsOf: sourceFileURL(named: "WorkspaceGitIdeaLogView.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("mainFramePrimaryColumn"), "标准 IDEA Log 应把 toolbar + table 收口到 MainFrame 左列，而不是继续挂在页面级头部")
        XCTAssertTrue(source.contains("mainFrameContent"), "标准 IDEA Log 应保留独立 MainFrame 容器")
        XCTAssertTrue(source.contains("var body: some View {\n        HStack(spacing: 0)"), "标准 IDEA Log 顶层应先进入 branches stripe + MainFrame 的横向布局")
        XCTAssertFalse(source.contains("var body: some View {\n        VStack(spacing: 0) {\n            WorkspaceGitIdeaLogToolbarView(viewModel: viewModel)"), "标准 IDEA Log 不应继续把 toolbar 直接放在整页 body 最顶层")
    }

    func testIdeaLogToolbarProvidesFiltersWithoutLegacyDetailPreviewToggles() throws {
        let source = try String(contentsOf: sourceFileURL(named: "WorkspaceGitIdeaLogToolbarView.swift"), encoding: .utf8)

        XCTAssertFalse(source.contains("branchFilterMenu"), "标准 IDEA Log toolbar 不应继续承担 branch filter 主入口；该职责应迁移到左侧 branches panel")
        XCTAssertFalse(source.contains("revisionTitle"), "标准 IDEA Log toolbar 不应继续维护旧的 revision title helper")
        XCTAssertTrue(source.contains("selectAuthorFilter"), "标准 IDEA Log toolbar 应提供 author filter")
        XCTAssertTrue(source.contains("selectDateFilter"), "标准 IDEA Log toolbar 应提供 date filter")
        XCTAssertTrue(source.contains("updatePathFilterQuery"), "标准 IDEA Log toolbar 应提供 path filter")
        XCTAssertFalse(source.contains("toggleDetails"), "标准 IDEA Log toolbar 不应继续保留旧的详情区显隐开关")
        XCTAssertFalse(source.contains("toggleDiffPreview"), "标准 IDEA Log toolbar 不应继续保留旧的 diff preview 显隐开关")
    }

    func testIdeaLogBranchesPanelProvidesSearchAndRefsTreeSections() throws {
        let source = try String(contentsOf: sourceFileURL(named: "WorkspaceGitIdeaLogBranchesPanelView.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("TextField("), "左侧 branches panel 应提供分支搜索框")
        XCTAssertTrue(source.contains("title: \"本地\""), "左侧 branches panel 应包含本地分支分组")
        XCTAssertTrue(source.contains("title: \"远端\""), "左侧 branches panel 应包含远端分支分组")
        XCTAssertTrue(source.contains("title: \"标签\""), "左侧 branches panel 应包含标签分组")
        XCTAssertTrue(source.contains("selectRevisionFilter"), "左侧 branches panel 应直接驱动 revision filter")
        XCTAssertTrue(source.contains("clearRevisionFilter"), "左侧 branches panel 应提供清空 revision filter 的显式入口")
    }

    func testIdeaLogBranchesPanelUsesDisplayTitleAndGroupCountHelpers() throws {
        let source = try String(contentsOf: sourceFileURL(named: "WorkspaceGitIdeaLogBranchesPanelView.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("selectedRevisionTitle"), "左侧 branches panel 应把当前 revision filter 显示标题收口到专用 helper，而不是直接展示原始 refs 路径")
        XCTAssertFalse(source.contains("Text(viewModel.selectedRevisionFilter ?? \"全部提交\")"), "左侧 branches panel header 不应继续直接展示原始 selectedRevisionFilter")
        XCTAssertTrue(source.contains("groupHeader("), "左侧 branches panel 应通过 group header helper 统一显示分组标题与数量")
        XCTAssertTrue(source.contains("count: localBranches.count"), "本地分支分组应显示数量")
        XCTAssertTrue(source.contains("count: remoteBranches.count"), "远端分支分组应显示数量")
        XCTAssertTrue(source.contains("count: tags.count"), "标签分组应显示数量")
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

    func testIdeaLogRightSidebarSeparatesChangesAndDetails() throws {
        let source = try String(contentsOf: sourceFileURL(named: "WorkspaceGitIdeaLogRightSidebarView.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("WorkspaceGitIdeaLogChangesView("), "标准 IDEA Log 左下区域应为 changes browser")
        XCTAssertTrue(source.contains("WorkspaceGitIdeaLogDetailsView("), "标准 IDEA Log 右下区域应为 commit details")
        XCTAssertTrue(source.contains("direction: .vertical"), "标准 IDEA Log 右侧信息栏内部应使用纵向 split 承接 changes 与 details")
    }

    func testIdeaLogDetailPanesUseCompactPaneHeadersAndMetadataSections() throws {
        let changesSource = try String(contentsOf: sourceFileURL(named: "WorkspaceGitIdeaLogChangesView.swift"), encoding: .utf8)
        let detailsSource = try String(contentsOf: sourceFileURL(named: "WorkspaceGitIdeaLogDetailsView.swift"), encoding: .utf8)

        XCTAssertTrue(changesSource.contains("paneHeader("), "changes browser 应收口为统一 pane header，而不是继续散落标题样式")
        XCTAssertTrue(changesSource.contains("fileSubtitle"), "changes browser 应提供 rename/copy 等补充信息，而不是只显示单行路径")
        XCTAssertTrue(detailsSource.contains("detailHeader"), "commit details 应包含紧凑 header，而不是直接从正文开始")
        XCTAssertTrue(detailsSource.contains("detailSection("), "commit details 应拆成稳定的 metadata / refs / parents section")
        XCTAssertTrue(detailsSource.contains("referencesSection"), "commit details 应单独呈现 refs 区域")
        XCTAssertTrue(detailsSource.contains("parentsSection"), "commit details 应单独呈现 parents 区域")
    }


    func testIdeaLogChangesViewUsesTreeBrowserAndToolbarLayout() throws {
        let source = try String(contentsOf: sourceFileURL(named: "WorkspaceGitIdeaLogChangesView.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("changesBrowserToolbar"), "Changes 区域应包含独立 toolbar，而不是只剩标题加扁平列表")
        XCTAssertTrue(source.contains("toolbarButton("), "Changes toolbar 应通过统一 helper 渲染 icon-only 小操作入口")
        XCTAssertTrue(source.contains("DisclosureGroup"), "Changes 区域应切换到可控展开状态的树形浏览器容器")
        XCTAssertTrue(source.contains("changeTreeRoots"), "Changes 区域应先构建树节点，再驱动渲染")
        XCTAssertFalse(source.contains("List(detail.files)"), "Changes 区域不应继续直接使用扁平文件列表")
    }


    func testIdeaLogChangesViewProvidesGlobalExpandCollapseControls() throws {
        let source = try String(contentsOf: sourceFileURL(named: "WorkspaceGitIdeaLogChangesView.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("expandedDirectoryIDs"), "Changes tree 应存在统一目录展开状态真相源")
        XCTAssertTrue(source.contains("expandAllDirectories"), "Changes toolbar 应提供展开全部 helper")
        XCTAssertTrue(source.contains("collapseAllDirectories"), "Changes toolbar 应提供折叠全部 helper")
        XCTAssertTrue(source.contains("allDirectoryIDs"), "Changes tree 应能计算所有目录节点 id 供全局展开使用")
        XCTAssertTrue(source.contains("title: \"展开全部\""), "Changes toolbar 应提供展开全部入口")
        XCTAssertTrue(source.contains("title: \"折叠全部\""), "Changes toolbar 应提供折叠全部入口")
        XCTAssertTrue(source.contains("DisclosureGroup"), "可控展开状态下，目录节点应改用 DisclosureGroup 渲染")
        XCTAssertFalse(source.contains("OutlineGroup"), "Changes tree 不应继续停留在无法程序化展开/折叠的 OutlineGroup")
    }

    func testIdeaLogChangesViewMapsExpandCollapseIconsToCorrectSemanticDirection() throws {
        let source = try String(contentsOf: sourceFileURL(named: "WorkspaceGitIdeaLogChangesView.swift"), encoding: .utf8)

        XCTAssertTrue(
            source.contains("toolbarButton(systemImage: \"arrow.up.left.and.arrow.down.right\", title: \"展开全部\")"),
            "展开全部应使用从中心向外发散的 icon，而不是向中心收拢的 icon"
        )
        XCTAssertTrue(
            source.contains("toolbarButton(systemImage: \"arrow.down.forward.and.arrow.up.backward\", title: \"折叠全部\")"),
            "折叠全部应使用向中心收拢的 icon，而不是向外发散的 icon"
        )
        XCTAssertFalse(
            source.contains("toolbarButton(systemImage: \"arrow.down.forward.and.arrow.up.backward\", title: \"展开全部\")"),
            "展开全部不应继续绑定收拢语义 icon"
        )
        XCTAssertFalse(
            source.contains("toolbarButton(systemImage: \"arrow.up.left.and.arrow.down.right\", title: \"折叠全部\")"),
            "折叠全部不应继续绑定发散语义 icon"
        )
    }

    func testIdeaLogChangesViewUsesFilenameAndPathHierarchyHelpers() throws {
        let source = try String(contentsOf: sourceFileURL(named: "WorkspaceGitIdeaLogChangesView.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("primaryFileName"), "changes browser 应显式拆出主文件名 helper，而不是直接把完整路径当主标题")
        XCTAssertTrue(source.contains("secondaryPathSubtitle"), "changes browser 应显式拆出次级路径 helper，承接父目录与 rename/copy 信息")
        XCTAssertFalse(source.contains("Text(file.path)"), "changes browser 不应继续直接把 file.path 作为唯一主文本")
    }

    func testIdeaLogDetailsViewClassifiesBranchAndTagBadges() throws {
        let source = try String(contentsOf: sourceFileURL(named: "WorkspaceGitIdeaLogDetailsView.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("branchReferenceItems"), "commit details 应把 refs 拆成 branch/HEAD 类引用")
        XCTAssertTrue(source.contains("tagReferenceItems"), "commit details 应把 refs 拆成 tag 类引用")
        XCTAssertTrue(source.contains("ReferenceBadgeStyle"), "commit details 应为不同 refs badge 提供显式样式枚举")
        XCTAssertTrue(source.contains("referenceBadge("), "commit details 应通过统一 helper 渲染 refs badge")
    }

    private func sourceFileURL(named name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/\(name)")
    }
}
