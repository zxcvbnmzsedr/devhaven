import XCTest
@testable import DevHavenCore

final class WorkspaceGitCommitGraphCoreTests: XCTestCase {
    func testBuildVisibleModelCreatesMultipleOutgoingEdgesForMergeCommit() throws {
        let visible = WorkspaceGitCommitGraphBuilder.buildVisibleModel(commits: mergeScenarioCommits())

        XCTAssertEqual(visible.rows.count, 4)
        let mergeRow = visible.rows[0]
        let mergeNode = try XCTUnwrap(mergeRow.node)
        XCTAssertEqual(mergeNode.column, 0)
        XCTAssertEqual(
            mergeRow.edgeElements.filter {
                $0.direction == .down
            }.count,
            2,
            "merge commit 应同时向第一父和第二父输出边，而不是只能画单条独立线"
        )
    }

    func testBuildVisibleModelKeepsLongEdgeAliveAcrossSiblingRowAndMigratesIntoMainLane() {
        let visible = WorkspaceGitCommitGraphBuilder.buildVisibleModel(commits: mergeScenarioCommits())

        let mainlineRow = visible.rows[2]
        let mainlineNodeColumn = mainlineRow.node?.column ?? -1
        XCTAssertEqual(mainlineNodeColumn, 0)
        let independentLaneColumn = mainlineRow.edgeElements
            .filter { $0.positionInCurrentRow != mainlineNodeColumn }
            .map(\.positionInCurrentRow)
            .max()
        XCTAssertTrue(
            independentLaneColumn != nil,
            "长边经过兄弟分支所在 row 时，应该继续作为独立 graph element 存活，而不是退化成当前 node 自己的单条线"
        )
        XCTAssertTrue(
            mainlineRow.edgeElements.contains(where: {
                $0.positionInCurrentRow == independentLaneColumn &&
                $0.positionInOtherRow == 0 &&
                $0.direction == .down
            }),
            "长边在接回主干时，应能从独立 lane 迁移回主干列，形成 merge 迁出形态"
        )
    }

    func testBuildVisibleModelUsesCurrentHeadDecorationAsPermanentLayoutPriority() {
        let visible = WorkspaceGitCommitGraphBuilder.buildVisibleModel(commits: prioritizedHeadScenarioCommits())

        XCTAssertLessThan(
            visible.permanentModel.layoutIndexByHash["main2"] ?? .max,
            visible.permanentModel.layoutIndexByHash["feature2"] ?? .max,
            "带 `HEAD ->` 的当前分支应优先占据更靠左的 permanent layout index"
        )
        XCTAssertEqual(
            visible.permanentModel.headHashesInLayoutOrder,
            ["main2", "feature2"],
            "head 排序应优先 current HEAD，再到其它分支头"
        )
    }

    func testBuildVisibleModelAssignsDifferentColorIndicesToDifferentBranchLanes() throws {
        let visible = WorkspaceGitCommitGraphBuilder.buildVisibleModel(commits: prioritizedHeadScenarioCommits())

        let currentBranchRow = visible.rows[1]
        let node = try XCTUnwrap(currentBranchRow.node)
        var colorValues = currentBranchRow.edgeElements.map { $0.colorIndex }
        colorValues.append(node.colorIndex)
        let laneColors = Set(colorValues)

        XCTAssertGreaterThanOrEqual(
            laneColors.count,
            2,
            "当前分支与旁侧独立 branch lane 应使用不同 color index，避免整张图谱只有单一 accent 色导致可读性和保真度都偏差"
        )
    }

    func testBuildVisibleModelShowsLongEdgeBesideHigherPriorityBranchHead() {
        let visible = WorkspaceGitCommitGraphBuilder.buildVisibleModel(commits: prioritizedHeadScenarioCommits())

        let currentBranchRow = visible.rows[1]
        let currentBranchNodeColumn = currentBranchRow.node?.column ?? -1
        XCTAssertEqual(currentBranchNodeColumn, 0)
        XCTAssertTrue(
            currentBranchRow.edgeElements.contains(where: {
                $0.positionInCurrentRow > currentBranchNodeColumn ||
                $0.positionInOtherRow > currentBranchNodeColumn
            }),
            "当前分支 head 下方若存在另一条更右侧长边，该长边应继续独立穿行，而不是被压扁回当前 node 列"
        )
    }

    func testBuildVisibleModelUsesAdjacentRowPositionsInsteadOfAnchorBoundaryPoints() throws {
        let visible = WorkspaceGitCommitGraphBuilder.buildVisibleModel(commits: mergeScenarioCommits())

        let row = visible.rows[0]
        XCTAssertTrue(
            row.edgeElements.allSatisfy { $0.direction == .down },
            "当前实现应像 IDEA print element 一样按当前 row 到相邻 row 的方向输出 edge"
        )
        XCTAssertTrue(
            row.edgeElements.contains(where: { $0.positionInCurrentRow != $0.positionInOtherRow }),
            "斜线连接应通过 current/other row position 差异表达，而不是 anchor 边界拼接"
        )
    }

    func testBuildVisibleModelShowsCarriedEdgeOnlyOnIntermediateRowsLikeIdeaEdgesInRowGenerator() {
        let visible = WorkspaceGitCommitGraphBuilder.buildVisibleModel(commits: mergeScenarioCommits())

        XCTAssertEqual(
            visible.rows[0].currentLaneCommitHashes,
            ["m"],
            "IDEA 的 EdgesInRowGenerator 只会让 carried edge 出现在 attachment 之间的中间 row；merge commit 所在行本身不应凭空多出独立 edge lane"
        )
        XCTAssertTrue(
            visible.rows[1].currentLaneCommitHashes.contains("m->a2"),
            "长边应从下一行开始作为独立可见 edge element 存活，供 line-to-line 连接继续沿用"
        )
    }

    func testBuildVisibleModelEmitsUpAndDownSegmentsOnNonTopNodeRowLikeIdeaPrintElements() throws {
        let visible = WorkspaceGitCommitGraphBuilder.buildVisibleModel(commits: mergeScenarioCommits())

        let row = visible.rows[1]
        let nodeColumn = try XCTUnwrap(row.node?.column)

        XCTAssertTrue(
            row.edgeElements.contains(where: {
                $0.direction == .up &&
                $0.positionInCurrentRow == nodeColumn
            }),
            "IDEA `getPrintElements(row)` 对非首行节点会在当前 row 输出向上 segment；否则来自上一行的线不会在当前 row 内直接接到节点"
        )
        XCTAssertTrue(
            row.edgeElements.contains(where: {
                $0.direction == .down &&
                $0.positionInCurrentRow == nodeColumn
            }),
            "IDEA `getPrintElements(row)` 也会在同一 row 输出向下 segment，使节点能在同一 row 内把上/下连线接起来"
        )
    }

    func testBuildVisibleModelProvidesRecommendedWidthFromVisibleGraph() {
        let visible = WorkspaceGitCommitGraphBuilder.buildVisibleModel(commits: mergeScenarioCommits())

        XCTAssertEqual(
            visible.recommendedLaneCount,
            2,
            "merge 场景应只保留真实可见的两条 lane；attachment row 上的 phantom edge lane 不应继续把推荐宽度虚增"
        )
        XCTAssertEqual(
            visible.recommendedWidth,
            WorkspaceGitCommitGraphBuilder.horizontalPadding * 2 +
                Double(visible.recommendedLaneCount - 1) * WorkspaceGitCommitGraphBuilder.columnSpacing,
            accuracy: 0.001
        )
    }

    private func mergeScenarioCommits() -> [WorkspaceGitCommitSummary] {
        [
            makeCommit(hash: "m", parents: ["a2", "b1"]),
            makeCommit(hash: "b1", parents: ["a1"]),
            makeCommit(hash: "a2", parents: ["a1"]),
            makeCommit(hash: "a1", parents: []),
        ]
    }

    private func prioritizedHeadScenarioCommits() -> [WorkspaceGitCommitSummary] {
        [
            makeCommit(hash: "feature2", parents: ["a1"], decorations: "feature"),
            makeCommit(hash: "main2", parents: ["a1"], decorations: "HEAD -> main"),
            makeCommit(hash: "a1", parents: []),
        ]
    }

    private func makeCommit(
        hash: String,
        parents: [String],
        decorations: String? = nil
    ) -> WorkspaceGitCommitSummary {
        WorkspaceGitCommitSummary(
            hash: hash,
            shortHash: hash,
            graphPrefix: "",
            parentHashes: parents,
            authorName: "DevHaven",
            authorEmail: "devhaven@example.com",
            authorTimestamp: 1,
            subject: hash,
            decorations: decorations
        )
    }
}
