import Foundation

public enum WorkspaceGitCommitGraphBuilder {
    public static let columnSpacing: Double = 16
    public static let horizontalPadding: Double = 4

    public static func buildVisibleModel(commits: [WorkspaceGitCommitSummary]) -> WorkspaceGitCommitGraphVisibleModel {
        let permanentModel = buildPermanentModel(commits: commits)
        guard !commits.isEmpty else {
            return WorkspaceGitCommitGraphVisibleModel(
                permanentModel: permanentModel,
                rows: [],
                recommendedLaneCount: 1,
                recommendedWidth: horizontalPadding * 2
            )
        }

        let edgeSpans = buildEdgeSpans(permanentModel: permanentModel)
        let rowElements = buildRowElements(rowCount: commits.count, edgeSpans: edgeSpans)
        let positionsByRow = buildPositionsByRow(
            rowElements: rowElements,
            edgeSpans: edgeSpans,
            permanentModel: permanentModel
        )

        let rows = commits.enumerated().map { rowIndex, commit in
            let nodeColumn = positionsByRow[rowIndex][.node(rowIndex)] ?? 0
            let nodeColorIndex = permanentModel.layoutIndexByHash[commit.hash] ?? 0
            let node = WorkspaceGitCommitGraphNodePrintElement(
                rowIndex: rowIndex,
                positionInCurrentRow: nodeColumn,
                colorIndex: nodeColorIndex
            )
            let edgeElements = visibleEdgeElements(
                for: rowIndex,
                rowElements: rowElements,
                edgeSpans: edgeSpans,
                positionsByRow: positionsByRow
            )

            let currentLaneCommitHashes = debugVisibleElementKeys(
                edgeSpans: edgeSpans,
                rowIndex: rowIndex,
                positionsByRow: positionsByRow,
                commits: commits
            )
            let nextLaneCommitHashes = rowIndex + 1 < rowElements.count
                ? debugVisibleElementKeys(
                    edgeSpans: edgeSpans,
                    rowIndex: rowIndex + 1,
                    positionsByRow: positionsByRow,
                    commits: commits
                )
                : []

            return WorkspaceGitCommitGraphVisibleRow(
                rowIndex: rowIndex,
                commit: commit,
                currentLaneCommitHashes: currentLaneCommitHashes,
                nextLaneCommitHashes: nextLaneCommitHashes,
                node: node,
                edgeElements: deduplicatedEdgeElements(edgeElements)
            )
        }

        let recommendedLaneCount = max(
            positionsByRow.map { ($0.values.max() ?? -1) + 1 }.max() ?? 1,
            1
        )
        let recommendedWidth = horizontalPadding * 2 + Double(max(recommendedLaneCount - 1, 0)) * columnSpacing
        return WorkspaceGitCommitGraphVisibleModel(
            permanentModel: permanentModel,
            rows: rows,
            recommendedLaneCount: recommendedLaneCount,
            recommendedWidth: recommendedWidth
        )
    }
}

private extension WorkspaceGitCommitGraphBuilder {
    struct WorkspaceGitCommitGraphEdgeSpan: Equatable {
        let id: Int
        let childRow: Int
        let parentRow: Int
        let childHash: String
        let parentHash: String
        let colorIndex: Int
    }

    enum RowElement: Hashable {
        case node(Int)
        case edge(Int)
    }

    static func buildPermanentModel(commits: [WorkspaceGitCommitSummary]) -> WorkspaceGitCommitGraphPermanentModel {
        let commitsByHash = Dictionary(uniqueKeysWithValues: commits.map { ($0.hash, $0) })
        let rowIndexByHash = Dictionary(uniqueKeysWithValues: commits.enumerated().map { ($0.element.hash, $0.offset) })
        var childHashesByHash = Dictionary(uniqueKeysWithValues: commits.map { ($0.hash, [String]()) })
        for commit in commits {
            for parentHash in commit.parentHashes where rowIndexByHash[parentHash] != nil {
                childHashesByHash[parentHash, default: []].append(commit.hash)
            }
        }

        let sortedHeadHashes = commits
            .enumerated()
            .filter { (childHashesByHash[$0.element.hash] ?? []).isEmpty }
            .sorted { lhs, rhs in
                headImportance(of: lhs.element, rowIndex: lhs.offset) < headImportance(of: rhs.element, rowIndex: rhs.offset)
            }
            .map(\.element.hash)

        var layoutIndexByHash: [String: Int] = [:]
        var headHashesInLayoutOrder: [String] = []
        var nextLayoutIndex = 0

        func nextUnassignedParentHash(for hash: String) -> String? {
            guard let commit = commitsByHash[hash] else {
                return nil
            }
            return commit.parentHashes.first {
                rowIndexByHash[$0] != nil && layoutIndexByHash[$0] == nil
            }
        }

        func walkFromHead(_ startHash: String) {
            var stack = [startHash]
            while let currentHash = stack.last {
                let firstVisit = layoutIndexByHash[currentHash] == nil
                if firstVisit {
                    layoutIndexByHash[currentHash] = nextLayoutIndex
                }

                if let nextHash = nextUnassignedParentHash(for: currentHash) {
                    stack.append(nextHash)
                    continue
                }

                if firstVisit {
                    nextLayoutIndex += 1
                }
                _ = stack.popLast()
            }
        }

        for headHash in sortedHeadHashes where layoutIndexByHash[headHash] == nil {
            headHashesInLayoutOrder.append(headHash)
            walkFromHead(headHash)
        }

        for commit in commits where layoutIndexByHash[commit.hash] == nil {
            walkFromHead(commit.hash)
        }

        return WorkspaceGitCommitGraphPermanentModel(
            commits: commits,
            rowIndexByHash: rowIndexByHash,
            childHashesByHash: childHashesByHash,
            layoutIndexByHash: layoutIndexByHash,
            headHashesInLayoutOrder: headHashesInLayoutOrder
        )
    }

    static func buildEdgeSpans(
        permanentModel: WorkspaceGitCommitGraphPermanentModel
    ) -> [WorkspaceGitCommitGraphEdgeSpan] {
        permanentModel.commits.enumerated().flatMap { rowIndex, commit in
            commit.parentHashes.enumerated().compactMap { parentOffset, parentHash in
                guard let parentRow = permanentModel.rowIndexByHash[parentHash], parentRow > rowIndex else {
                    return nil
                }
                return WorkspaceGitCommitGraphEdgeSpan(
                    id: stableEdgeIdentifier(childRow: rowIndex, parentRow: parentRow),
                    childRow: rowIndex,
                    parentRow: parentRow,
                    childHash: commit.hash,
                    parentHash: parentHash,
                    colorIndex: edgeColorIndex(
                        childHash: commit.hash,
                        parentHash: parentHash,
                        parentOffset: parentOffset,
                        permanentModel: permanentModel
                    )
                )
            }
        }
    }

    static func buildRowElements(
        rowCount: Int,
        edgeSpans: [WorkspaceGitCommitGraphEdgeSpan]
    ) -> [[RowElement]] {
        var rows = Array(repeating: [RowElement](), count: rowCount)
        for rowIndex in 0..<rowCount {
            rows[rowIndex].append(.node(rowIndex))
        }
        for edge in edgeSpans {
            for rowIndex in (edge.childRow + 1)..<edge.parentRow {
                rows[rowIndex].append(.edge(edge.id))
            }
        }
        return rows
    }

    static func buildPositionsByRow(
        rowElements: [[RowElement]],
        edgeSpans: [WorkspaceGitCommitGraphEdgeSpan],
        permanentModel: WorkspaceGitCommitGraphPermanentModel
    ) -> [[RowElement: Int]] {
        let edgeByID = Dictionary(uniqueKeysWithValues: edgeSpans.map { ($0.id, $0) })
        return rowElements.enumerated().map { _, elements in
            let stableElements = elements.enumerated().sorted { lhs, rhs in
                let result = compare(
                    lhs.element,
                    rhs.element,
                    edgeByID: edgeByID,
                    permanentModel: permanentModel
                )
                if result == 0 {
                    return lhs.offset < rhs.offset
                }
                return result < 0
            }

            var positions: [RowElement: Int] = [:]
            for (index, pair) in stableElements.enumerated() {
                positions[pair.element] = index
            }
            return positions
        }
    }

    static func position(
        of edge: WorkspaceGitCommitGraphEdgeSpan,
        at rowIndex: Int,
        positionsByRow: [[RowElement: Int]]
    ) -> Int {
        if rowIndex == edge.childRow {
            return positionsByRow[rowIndex][.node(rowIndex)] ?? 0
        }
        if rowIndex == edge.parentRow {
            return positionsByRow[rowIndex][.node(rowIndex)] ?? 0
        }
        return positionsByRow[rowIndex][.edge(edge.id)] ?? 0
    }

    static func visibleEdgeElements(
        for rowIndex: Int,
        rowElements: [[RowElement]],
        edgeSpans: [WorkspaceGitCommitGraphEdgeSpan],
        positionsByRow: [[RowElement: Int]]
    ) -> [WorkspaceGitCommitGraphEdgePrintElement] {
        guard rowIndex >= 0, rowIndex < positionsByRow.count else {
            return []
        }

        let edgeByID = Dictionary(uniqueKeysWithValues: edgeSpans.map { ($0.id, $0) })
        let nodeElement = RowElement.node(rowIndex)
        let nodeColumn = positionsByRow[rowIndex][nodeElement] ?? 0
        var printElements: [WorkspaceGitCommitGraphEdgePrintElement] = []

        let adjacentNodeEdges = edgeSpans.filter { edge in
            edge.childRow == rowIndex || edge.parentRow == rowIndex
        }
        for edge in adjacentNodeEdges {
            if rowIndex > edge.childRow {
                printElements.append(
                    WorkspaceGitCommitGraphEdgePrintElement(
                        rowIndex: rowIndex,
                        positionInCurrentRow: nodeColumn,
                        positionInOtherRow: position(of: edge, at: rowIndex - 1, positionsByRow: positionsByRow),
                        direction: .up,
                        colorIndex: edge.colorIndex
                    )
                )
            }
            if rowIndex < edge.parentRow {
                printElements.append(
                    WorkspaceGitCommitGraphEdgePrintElement(
                        rowIndex: rowIndex,
                        positionInCurrentRow: nodeColumn,
                        positionInOtherRow: position(of: edge, at: rowIndex + 1, positionsByRow: positionsByRow),
                        direction: .down,
                        colorIndex: edge.colorIndex
                    )
                )
            }
        }

        for element in rowElements[rowIndex] {
            guard case let .edge(edgeID) = element, let edge = edgeByID[edgeID] else {
                continue
            }
            let currentColumn = positionsByRow[rowIndex][element] ?? 0
            if rowIndex > edge.childRow {
                printElements.append(
                    WorkspaceGitCommitGraphEdgePrintElement(
                        rowIndex: rowIndex,
                        positionInCurrentRow: currentColumn,
                        positionInOtherRow: position(of: edge, at: rowIndex - 1, positionsByRow: positionsByRow),
                        direction: .up,
                        colorIndex: edge.colorIndex
                    )
                )
            }
            if rowIndex < edge.parentRow {
                printElements.append(
                    WorkspaceGitCommitGraphEdgePrintElement(
                        rowIndex: rowIndex,
                        positionInCurrentRow: currentColumn,
                        positionInOtherRow: position(of: edge, at: rowIndex + 1, positionsByRow: positionsByRow),
                        direction: .down,
                        colorIndex: edge.colorIndex
                    )
                )
            }
        }

        return printElements
    }

    static func compare(
        _ lhs: RowElement,
        _ rhs: RowElement,
        edgeByID: [Int: WorkspaceGitCommitGraphEdgeSpan],
        permanentModel: WorkspaceGitCommitGraphPermanentModel
    ) -> Int {
        switch (lhs, rhs) {
        case let (.node(lhsRow), .node(rhsRow)):
            let lhsLayout = permanentModel.layoutIndexByHash[permanentModel.commits[lhsRow].hash] ?? lhsRow
            let rhsLayout = permanentModel.layoutIndexByHash[permanentModel.commits[rhsRow].hash] ?? rhsRow
            if lhsLayout != rhsLayout {
                return lhsLayout - rhsLayout
            }
            return lhsRow - rhsRow

        case let (.edge(lhsID), .edge(rhsID)):
            guard let lhsEdge = edgeByID[lhsID], let rhsEdge = edgeByID[rhsID] else {
                return lhsID - rhsID
            }
            return compareEdges(lhsEdge, rhsEdge, permanentModel: permanentModel)

        case let (.edge(lhsID), .node(rhsRow)):
            guard let lhsEdge = edgeByID[lhsID] else {
                return -1
            }
            return compareEdge(lhsEdge, toNodeRow: rhsRow, permanentModel: permanentModel)

        case let (.node(lhsRow), .edge(rhsID)):
            guard let rhsEdge = edgeByID[rhsID] else {
                return 1
            }
            return -compareEdge(rhsEdge, toNodeRow: lhsRow, permanentModel: permanentModel)
        }
    }

    static func compareEdges(
        _ lhs: WorkspaceGitCommitGraphEdgeSpan,
        _ rhs: WorkspaceGitCommitGraphEdgeSpan,
        permanentModel: WorkspaceGitCommitGraphPermanentModel
    ) -> Int {
        if lhs.childRow == rhs.childRow {
            if lhs.parentRow < rhs.parentRow {
                return -compareEdge(rhs, toNodeRow: lhs.parentRow, permanentModel: permanentModel)
            }
            return compareEdge(lhs, toNodeRow: rhs.parentRow, permanentModel: permanentModel)
        }

        if lhs.childRow < rhs.childRow {
            return compareEdge(lhs, toNodeRow: rhs.childRow, permanentModel: permanentModel)
        }
        return -compareEdge(rhs, toNodeRow: lhs.childRow, permanentModel: permanentModel)
    }

    static func compareEdge(
        _ edge: WorkspaceGitCommitGraphEdgeSpan,
        toNodeRow nodeRow: Int,
        permanentModel: WorkspaceGitCommitGraphPermanentModel
    ) -> Int {
        let upLayout = permanentLayoutIndex(forRow: edge.childRow, permanentModel: permanentModel)
        let downLayout = permanentLayoutIndex(forRow: edge.parentRow, permanentModel: permanentModel)
        let nodeLayout = permanentLayoutIndex(forRow: nodeRow, permanentModel: permanentModel)
        let dominantLayout = max(upLayout, downLayout)
        if dominantLayout != nodeLayout {
            return dominantLayout - nodeLayout
        }
        return edge.childRow - nodeRow
    }

    static func permanentLayoutIndex(
        forRow rowIndex: Int,
        permanentModel: WorkspaceGitCommitGraphPermanentModel
    ) -> Int {
        let hash = permanentModel.commits[rowIndex].hash
        return permanentModel.layoutIndexByHash[hash] ?? rowIndex
    }

    static func stableEdgeIdentifier(childRow: Int, parentRow: Int) -> Int {
        (childRow << 16) ^ parentRow
    }

    static func edgeColorIndex(
        childHash: String,
        parentHash: String,
        parentOffset: Int,
        permanentModel: WorkspaceGitCommitGraphPermanentModel
    ) -> Int {
        if parentOffset == 0 {
            return permanentModel.layoutIndexByHash[childHash] ?? 0
        }
        return permanentModel.layoutIndexByHash[parentHash] ?? permanentModel.layoutIndexByHash[childHash] ?? 0
    }

    static func deduplicatedEdgeElements(
        _ edgeElements: [WorkspaceGitCommitGraphEdgePrintElement]
    ) -> [WorkspaceGitCommitGraphEdgePrintElement] {
        var deduplicated: [WorkspaceGitCommitGraphEdgePrintElement] = []
        for edge in edgeElements where !deduplicated.contains(edge) {
            deduplicated.append(edge)
        }
        return deduplicated
    }

    static func debugVisibleElementKeys(
        edgeSpans: [WorkspaceGitCommitGraphEdgeSpan],
        rowIndex: Int,
        positionsByRow: [[RowElement: Int]],
        commits: [WorkspaceGitCommitSummary]
    ) -> [String] {
        let edgeByID = Dictionary(uniqueKeysWithValues: edgeSpans.map { ($0.id, $0) })
        return positionsByRow[rowIndex]
            .sorted { lhs, rhs in lhs.value < rhs.value }
            .map(\.key)
            .map { element in
            switch element {
            case .node:
                return commits[rowIndex].hash
            case let .edge(edgeID):
                guard let edge = edgeByID[edgeID] else {
                    return "edge@\(edgeID)"
                }
                return "\(edge.childHash)->\(edge.parentHash)"
            }
        }
    }

    static func headImportance(
        of commit: WorkspaceGitCommitSummary,
        rowIndex: Int
    ) -> WorkspaceGitCommitGraphHeadImportance {
        let tokens = decorationTokens(from: commit.decorations)
        if tokens.contains(where: { $0.hasPrefix("HEAD -> ") }) {
            return WorkspaceGitCommitGraphHeadImportance(rank: 0, rowIndex: rowIndex)
        }
        if tokens.contains(where: { !$0.hasPrefix("tag: ") }) {
            return WorkspaceGitCommitGraphHeadImportance(rank: 1, rowIndex: rowIndex)
        }
        if !tokens.isEmpty {
            return WorkspaceGitCommitGraphHeadImportance(rank: 2, rowIndex: rowIndex)
        }
        return WorkspaceGitCommitGraphHeadImportance(rank: 3, rowIndex: rowIndex)
    }

    static func decorationTokens(from decorations: String?) -> [String] {
        guard let decorations else {
            return []
        }
        return decorations
            .trimmingCharacters(in: CharacterSet(charactersIn: "() ").union(.whitespacesAndNewlines))
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private struct WorkspaceGitCommitGraphHeadImportance: Comparable {
    let rank: Int
    let rowIndex: Int

    static func < (lhs: WorkspaceGitCommitGraphHeadImportance, rhs: WorkspaceGitCommitGraphHeadImportance) -> Bool {
        if lhs.rank != rhs.rank {
            return lhs.rank < rhs.rank
        }
        return lhs.rowIndex < rhs.rowIndex
    }
}
