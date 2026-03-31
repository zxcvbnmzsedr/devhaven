import XCTest
@testable import DevHavenCore

final class WorkspaceGitCommitGraphBuilderTests: XCTestCase {
    func testBuildVisibleModelKeepsMergeConnectionsAndDeduplicatedEdgeElements() {
        let commits = [
            makeCommit(hash: "merge", parents: ["feature", "main"], decorations: "HEAD -> main"),
            makeCommit(hash: "feature", parents: ["base"]),
            makeCommit(hash: "main", parents: ["base"]),
            makeCommit(hash: "base", parents: [])
        ]

        let model = WorkspaceGitCommitGraphBuilder.buildVisibleModel(commits: commits)

        XCTAssertEqual(model.rows.count, 4)
        XCTAssertEqual(
            model.rows[0].edgeElements.filter { $0.direction == .down }.count,
            2,
            "merge commit 顶行应同时连向两个父提交"
        )
        XCTAssertTrue(
            model.rows.allSatisfy { row in
                uniqueEdgeElementCount(in: row.edgeElements) == row.edgeElements.count
            },
            "graph builder 输出不应包含重复 edge print elements"
        )
    }

    func testBuildVisibleModelSkipsDebugLaneKeysByDefault() {
        let commits = [
            makeCommit(hash: "c1", parents: ["c2"]),
            makeCommit(hash: "c2", parents: [])
        ]

        let model = WorkspaceGitCommitGraphBuilder.buildVisibleModel(commits: commits)

        XCTAssertTrue(model.rows.allSatisfy(\.currentLaneCommitHashes.isEmpty))
        XCTAssertTrue(model.rows.allSatisfy(\.nextLaneCommitHashes.isEmpty))
    }

    private func makeCommit(
        hash: String,
        parents: [String],
        decorations: String? = nil
    ) -> WorkspaceGitCommitSummary {
        WorkspaceGitCommitSummary(
            hash: hash,
            shortHash: String(hash.prefix(7)),
            graphPrefix: "*",
            parentHashes: parents,
            authorName: "Alice",
            authorEmail: "alice@example.com",
            authorTimestamp: 1_710_000_000,
            subject: hash,
            decorations: decorations
        )
    }

    private func uniqueEdgeElementCount(in edgeElements: [WorkspaceGitCommitGraphEdgePrintElement]) -> Int {
        Set(
            edgeElements.map {
                "\($0.rowIndex)|\($0.positionInCurrentRow)|\($0.positionInOtherRow)|\($0.direction.rawValue)|\($0.colorIndex)"
            }
        ).count
    }
}
