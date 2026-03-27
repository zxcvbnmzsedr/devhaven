import Foundation

public enum WorkspaceGitCommitGraphEdgeDirection: String, Equatable, Sendable {
    case up
    case down
}

public struct WorkspaceGitCommitGraphNodePrintElement: Equatable, Sendable {
    public var rowIndex: Int
    public var positionInCurrentRow: Int
    public var colorIndex: Int

    public var column: Int { positionInCurrentRow }

    public init(rowIndex: Int, positionInCurrentRow: Int, colorIndex: Int) {
        self.rowIndex = rowIndex
        self.positionInCurrentRow = positionInCurrentRow
        self.colorIndex = colorIndex
    }
}

public struct WorkspaceGitCommitGraphEdgePrintElement: Equatable, Sendable {
    public var rowIndex: Int
    public var positionInCurrentRow: Int
    public var positionInOtherRow: Int
    public var direction: WorkspaceGitCommitGraphEdgeDirection
    public var colorIndex: Int

    public init(
        rowIndex: Int,
        positionInCurrentRow: Int,
        positionInOtherRow: Int,
        direction: WorkspaceGitCommitGraphEdgeDirection,
        colorIndex: Int
    ) {
        self.rowIndex = rowIndex
        self.positionInCurrentRow = positionInCurrentRow
        self.positionInOtherRow = positionInOtherRow
        self.direction = direction
        self.colorIndex = colorIndex
    }
}

public struct WorkspaceGitCommitGraphVisibleRow: Equatable, Sendable {
    public var rowIndex: Int
    public var commit: WorkspaceGitCommitSummary
    public var currentLaneCommitHashes: [String]
    public var nextLaneCommitHashes: [String]
    public var node: WorkspaceGitCommitGraphNodePrintElement?
    public var edgeElements: [WorkspaceGitCommitGraphEdgePrintElement]

    public init(
        rowIndex: Int,
        commit: WorkspaceGitCommitSummary,
        currentLaneCommitHashes: [String],
        nextLaneCommitHashes: [String],
        node: WorkspaceGitCommitGraphNodePrintElement?,
        edgeElements: [WorkspaceGitCommitGraphEdgePrintElement]
    ) {
        self.rowIndex = rowIndex
        self.commit = commit
        self.currentLaneCommitHashes = currentLaneCommitHashes
        self.nextLaneCommitHashes = nextLaneCommitHashes
        self.node = node
        self.edgeElements = edgeElements
    }
}

public struct WorkspaceGitCommitGraphPermanentModel: Equatable, Sendable {
    public var commits: [WorkspaceGitCommitSummary]
    public var commitsByHash: [String: WorkspaceGitCommitSummary]
    public var rowIndexByHash: [String: Int]
    public var childHashesByHash: [String: [String]]
    public var layoutIndexByHash: [String: Int]
    public var headHashesInLayoutOrder: [String]

    public init(
        commits: [WorkspaceGitCommitSummary],
        rowIndexByHash: [String: Int],
        childHashesByHash: [String: [String]],
        layoutIndexByHash: [String: Int],
        headHashesInLayoutOrder: [String]
    ) {
        self.commits = commits
        self.commitsByHash = Dictionary(uniqueKeysWithValues: commits.map { ($0.hash, $0) })
        self.rowIndexByHash = rowIndexByHash
        self.childHashesByHash = childHashesByHash
        self.layoutIndexByHash = layoutIndexByHash
        self.headHashesInLayoutOrder = headHashesInLayoutOrder
    }
}

public struct WorkspaceGitCommitGraphVisibleModel: Equatable, Sendable {
    public var permanentModel: WorkspaceGitCommitGraphPermanentModel
    public var rows: [WorkspaceGitCommitGraphVisibleRow]
    public var recommendedLaneCount: Int
    public var recommendedWidth: Double

    public init(
        permanentModel: WorkspaceGitCommitGraphPermanentModel,
        rows: [WorkspaceGitCommitGraphVisibleRow],
        recommendedLaneCount: Int,
        recommendedWidth: Double
    ) {
        self.permanentModel = permanentModel
        self.rows = rows
        self.recommendedLaneCount = recommendedLaneCount
        self.recommendedWidth = recommendedWidth
    }
}
