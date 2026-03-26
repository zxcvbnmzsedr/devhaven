import Foundation

public struct WorkspaceDiffRequestItem: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var source: WorkspaceDiffSource
    public var preferredViewerMode: WorkspaceDiffViewerMode

    public init(
        id: String,
        title: String,
        source: WorkspaceDiffSource,
        preferredViewerMode: WorkspaceDiffViewerMode = .sideBySide
    ) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.source = source
        self.preferredViewerMode = preferredViewerMode
    }
}

public struct WorkspaceDiffRequestChain: Equatable, Sendable {
    public var items: [WorkspaceDiffRequestItem]
    public var activeIndex: Int

    public init(
        items: [WorkspaceDiffRequestItem],
        activeIndex: Int = 0
    ) {
        self.items = items
        self.activeIndex = Self.clampIndex(activeIndex, count: items.count)
    }

    public var activeItem: WorkspaceDiffRequestItem? {
        guard items.indices.contains(activeIndex) else {
            return nil
        }
        return items[activeIndex]
    }

    public var totalItems: Int {
        items.count
    }

    public func updatingActiveIndex(_ index: Int) -> WorkspaceDiffRequestChain {
        WorkspaceDiffRequestChain(items: items, activeIndex: index)
    }

    private static func clampIndex(_ index: Int, count: Int) -> Int {
        guard count > 0 else {
            return 0
        }
        return min(max(0, index), count - 1)
    }
}

public struct WorkspaceDiffNavigatorState: Equatable, Sendable {
    public var requestChain: WorkspaceDiffRequestChain
    public var currentDifferenceIndex: Int
    public var totalDifferences: Int

    public init(
        requestChain: WorkspaceDiffRequestChain,
        currentDifferenceIndex: Int,
        totalDifferences: Int
    ) {
        let clampedTotalDifferences = max(0, totalDifferences)
        self.requestChain = requestChain
        self.totalDifferences = clampedTotalDifferences
        if clampedTotalDifferences == 0 {
            self.currentDifferenceIndex = 0
        } else {
            self.currentDifferenceIndex = min(max(1, currentDifferenceIndex), clampedTotalDifferences)
        }
    }

    public var currentRequestIndex: Int {
        guard requestChain.totalItems > 0 else {
            return 0
        }
        return requestChain.activeIndex + 1
    }

    public var totalRequests: Int {
        requestChain.totalItems
    }

    public var canGoPrevious: Bool {
        (totalDifferences > 0 && currentDifferenceIndex > 1) || requestChain.activeIndex > 0
    }

    public var canGoNext: Bool {
        (totalDifferences > 0 && currentDifferenceIndex < totalDifferences)
            || requestChain.activeIndex < max(0, requestChain.totalItems - 1)
    }
}

public enum WorkspaceDiffDifferenceAnchor: Equatable, Sendable {
    case compareBlock(String)
    case mergeConflict(String)
    case patchHunk(Int)
}

public struct WorkspaceDiffSessionState: Equatable, Sendable {
    public var requestChain: WorkspaceDiffRequestChain
    public var navigatorState: WorkspaceDiffNavigatorState

    public init(
        requestChain: WorkspaceDiffRequestChain,
        navigatorState: WorkspaceDiffNavigatorState? = nil
    ) {
        self.requestChain = requestChain
        self.navigatorState = navigatorState
            ?? WorkspaceDiffNavigatorState(
                requestChain: requestChain,
                currentDifferenceIndex: 0,
                totalDifferences: 0
            )
    }

    public var activeRequestItem: WorkspaceDiffRequestItem? {
        requestChain.activeItem
    }
}
