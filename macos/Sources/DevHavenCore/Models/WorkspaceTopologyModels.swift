import CoreGraphics
import Foundation

public enum WorkspacePaneSplitDirection: Sendable {
    case left
    case right
    case top
    case down

    var axis: WorkspaceSplitAxis {
        switch self {
        case .left, .right:
            return .horizontal
        case .top, .down:
            return .vertical
        }
    }
}

public enum WorkspacePaneFocusDirection: Sendable {
    case previous
    case next
    case left
    case right
    case top
    case down
}

public enum WorkspaceSplitAxis: String, Codable, Equatable, Sendable {
    case horizontal
    case vertical
}

public enum WorkspacePaneItemKind: String, Codable, Equatable, Sendable {
    case terminal
    case browser
}

public struct WorkspacePaneItemState: Identifiable, Equatable, Sendable {
    public var request: WorkspaceTerminalLaunchRequest
    public var title: String
    public var kind: WorkspacePaneItemKind
    public var browserState: WorkspaceBrowserState?

    public var id: String { request.surfaceId }

    public init(
        request: WorkspaceTerminalLaunchRequest,
        title: String,
        kind: WorkspacePaneItemKind = .terminal,
        browserState: WorkspaceBrowserState? = nil
    ) {
        self.request = request
        self.title = title
        self.kind = kind
        self.browserState = browserState
    }

    public func rebinding(
        tabId: String? = nil,
        paneId: String
    ) -> WorkspacePaneItemState {
        WorkspacePaneItemState(
            request: request.rebinding(tabId: tabId, paneId: paneId),
            title: title,
            kind: kind,
            browserState: browserState?.rebinding(tabId: tabId, paneId: paneId)
        )
    }

    public var isTerminal: Bool {
        kind == .terminal
    }

    public var isBrowser: Bool {
        kind == .browser
    }
}

public struct WorkspacePaneState: Identifiable, Equatable, Sendable {
    public var paneId: String
    public var items: [WorkspacePaneItemState]
    public var selectedItemId: String

    public var id: String { paneId }

    public init(
        paneId: String,
        items: [WorkspacePaneItemState],
        selectedItemId: String
    ) {
        self.paneId = paneId
        self.items = items
        self.selectedItemId = selectedItemId
        normalizeSelectedItem()
    }

    public init(
        request: WorkspaceTerminalLaunchRequest,
        title: String = "终端"
    ) {
        let item = WorkspacePaneItemState(request: request, title: title)
        self.init(
            paneId: request.paneId,
            items: [item],
            selectedItemId: item.id
        )
    }

    public var selectedItem: WorkspacePaneItemState? {
        items.first(where: { $0.id == selectedItemId }) ?? items.last
    }

    public var request: WorkspaceTerminalLaunchRequest {
        guard let selectedItem else {
            preconditionFailure("Workspace pane 缺少 terminal item，无法解析当前 request")
        }
        return selectedItem.request
    }

    public var selectedTerminalRequest: WorkspaceTerminalLaunchRequest? {
        selectedItem?.isTerminal == true ? selectedItem?.request : nil
    }

    public var selectedBrowserState: WorkspaceBrowserState? {
        selectedItem?.isBrowser == true ? selectedItem?.browserState : nil
    }

    public var selectedTitle: String {
        selectedItem?.title ?? "终端"
    }

    public var selectedIndex: Int? {
        items.firstIndex(where: { $0.id == selectedItemId })
    }

    public var hasMultipleItems: Bool {
        items.count > 1
    }

    public mutating func appendItem(_ item: WorkspacePaneItemState, select: Bool = true) {
        items.append(item)
        if select {
            selectedItemId = item.id
        }
        normalizeSelectedItem()
    }

    public mutating func insertItem(
        _ item: WorkspacePaneItemState,
        at index: Int? = nil,
        select: Bool = true
    ) {
        let resolvedIndex = min(max(index ?? items.count, 0), items.count)
        items.insert(item, at: resolvedIndex)
        if select {
            selectedItemId = item.id
        }
        normalizeSelectedItem()
    }

    @discardableResult
    public mutating func removeItem(id itemID: String) -> WorkspacePaneItemState? {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            return nil
        }
        let removed = items.remove(at: index)
        if selectedItemId == itemID {
            let fallbackIndex = min(index, max(items.count - 1, 0))
            selectedItemId = items.indices.contains(fallbackIndex)
                ? items[fallbackIndex].id
                : ""
        }
        normalizeSelectedItem()
        return removed
    }

    public mutating func selectItem(_ itemID: String) {
        guard items.contains(where: { $0.id == itemID }) else {
            return
        }
        selectedItemId = itemID
    }

    public mutating func moveItem(id itemID: String, by amount: Int) {
        guard let currentIndex = items.firstIndex(where: { $0.id == itemID }) else {
            return
        }
        let targetIndex = min(max(currentIndex + amount, 0), items.count - 1)
        guard targetIndex != currentIndex else {
            return
        }
        let item = items.remove(at: currentIndex)
        items.insert(item, at: targetIndex)
        selectedItemId = itemID
        normalizeSelectedItem()
    }

    public mutating func closeOtherItems(keeping itemID: String) {
        guard items.contains(where: { $0.id == itemID }) else {
            return
        }
        items = items.filter { $0.id == itemID }
        selectedItemId = itemID
    }

    public mutating func closeItemsToRight(of itemID: String) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            return
        }
        items = Array(items.prefix(index + 1))
        normalizeSelectedItem()
    }

    public mutating func updateItemTitle(id itemID: String, title: String) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            return
        }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        items[index].title = trimmed
        if items[index].isBrowser {
            items[index].browserState = items[index].browserState?.updating(title: trimmed)
        }
    }

    @discardableResult
    public mutating func updateBrowserItemState(
        id itemID: String,
        title: String? = nil,
        urlString: String? = nil,
        isLoading: Bool? = nil
    ) -> WorkspaceBrowserState? {
        guard let index = items.firstIndex(where: { $0.id == itemID }),
              items[index].isBrowser
        else {
            return nil
        }
        let currentState = items[index].browserState
            ?? WorkspaceBrowserState(
                surfaceId: items[index].id,
                projectPath: items[index].request.projectPath,
                tabId: items[index].request.tabId,
                paneId: items[index].request.paneId,
                title: items[index].title
            )
        let nextState = currentState.updating(
            title: title,
            urlString: urlString,
            isLoading: isLoading
        )
        items[index].browserState = nextState
        let trimmedTitle = nextState.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            items[index].title = trimmedTitle
        }
        return nextState
    }

    private mutating func normalizeSelectedItem() {
        if items.isEmpty {
            selectedItemId = ""
        } else if !items.contains(where: { $0.id == selectedItemId }) {
            selectedItemId = items.last?.id ?? ""
        }
    }
}

public struct WorkspaceSplitState: Equatable, Sendable {
    public var direction: WorkspaceSplitAxis
    public var ratio: Double
    public var left: WorkspacePaneTree.Node
    public var right: WorkspacePaneTree.Node

    public init(
        direction: WorkspaceSplitAxis,
        ratio: Double,
        left: WorkspacePaneTree.Node,
        right: WorkspacePaneTree.Node
    ) {
        self.direction = direction
        self.ratio = ratio
        self.left = left
        self.right = right
    }
}

public struct WorkspacePaneTree: Equatable, Sendable {
    public indirect enum Node: Equatable, Sendable {
        case leaf(WorkspacePaneState)
        case split(WorkspaceSplitState)
    }

    public enum PathComponent: Hashable, Sendable {
        case left
        case right
    }

    public struct Path: Hashable, Sendable {
        public var components: [PathComponent]

        public init(components: [PathComponent]) {
            self.components = components
        }

        public var isEmpty: Bool {
            components.isEmpty
        }

        func appending(_ component: PathComponent) -> Path {
            Path(components: components + [component])
        }
    }

    public struct LeafFrame: Equatable, Sendable {
        public var pane: WorkspacePaneState
        public var frame: CGRect

        public init(pane: WorkspacePaneState, frame: CGRect) {
            self.pane = pane
            self.frame = frame
        }
    }

    public struct SplitHandle: Equatable, Sendable {
        public var path: Path
        public var direction: WorkspaceSplitAxis
        public var splitBounds: CGRect
        public var visibleFrame: CGRect
        public var hitFrame: CGRect

        public init(
            path: Path,
            direction: WorkspaceSplitAxis,
            splitBounds: CGRect,
            visibleFrame: CGRect,
            hitFrame: CGRect
        ) {
            self.path = path
            self.direction = direction
            self.splitBounds = splitBounds
            self.visibleFrame = visibleFrame
            self.hitFrame = hitFrame
        }
    }

    public var root: Node?
    public var zoomedPaneId: String?

    public init(root: Node? = nil, zoomedPaneId: String? = nil) {
        self.root = root
        self.zoomedPaneId = zoomedPaneId
    }

    public var isEmpty: Bool {
        root == nil
    }

    public var leaves: [WorkspacePaneState] {
        root?.leaves() ?? []
    }

    public var rootSplit: WorkspaceSplitState? {
        guard let root else { return nil }
        guard case let .split(split) = root else { return nil }
        return split
    }

    public var structuralIdentity: StructuralIdentity {
        StructuralIdentity(self)
    }

    public struct StructuralIdentity: Hashable, Sendable {
        private let root: Node?
        private let zoomedPaneId: String?

        init(_ tree: WorkspacePaneTree) {
            self.root = tree.root
            self.zoomedPaneId = tree.zoomedPaneId
        }

        public static func == (lhs: Self, rhs: Self) -> Bool {
            areNodesStructurallyEqual(lhs.root, rhs.root) && lhs.zoomedPaneId == rhs.zoomedPaneId
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(0)
            if let root {
                root.hashStructure(into: &hasher)
            }
            hasher.combine(1)
            hasher.combine(zoomedPaneId)
        }

        private static func areNodesStructurallyEqual(_ lhs: Node?, _ rhs: Node?) -> Bool {
            switch (lhs, rhs) {
            case (nil, nil):
                return true
            case let (left?, right?):
                return left.isStructurallyEqual(to: right)
            default:
                return false
            }
        }
    }

    public func find(paneID: String?) -> WorkspacePaneState? {
        guard let paneID, let root else { return nil }
        return root.find(paneID: paneID)
    }

    public func path(to paneID: String?) -> Path? {
        guard let paneID, let root else { return nil }
        return root.path(to: paneID)
    }

    public func node(at path: Path) -> Node? {
        guard let root else { return nil }
        return root.node(at: path)
    }

    @discardableResult
    public mutating func insertPane(
        _ pane: WorkspacePaneState,
        at anchorPaneID: String,
        direction: WorkspacePaneSplitDirection
    ) -> Bool {
        guard let root, let path = root.path(to: anchorPaneID) else {
            return false
        }
        self.root = root.inserting(pane: pane, at: path, direction: direction)
        zoomedPaneId = nil
        return true
    }

    @discardableResult
    public mutating func removePane(_ paneID: String?) -> Bool {
        guard let paneID, let root else {
            return false
        }
        guard root.find(paneID: paneID) != nil else {
            return false
        }
        self.root = root.removing(paneID: paneID)
        if zoomedPaneId == paneID {
            zoomedPaneId = nil
        }
        return true
    }

    public mutating func equalize() {
        guard let root else { return }
        self.root = root.equalized()
    }

    public mutating func toggleZoom(on paneID: String?) {
        guard let paneID, find(paneID: paneID) != nil else { return }
        if zoomedPaneId == paneID {
            zoomedPaneId = nil
        } else {
            zoomedPaneId = paneID
        }
    }

    public mutating func setSplitRatio(at path: Path, ratio: Double) {
        guard let root else { return }
        self.root = root.settingSplitRatio(at: path, ratio: min(max(ratio, 0.1), 0.9))
    }

    public func replacingPane(at path: Path, with pane: WorkspacePaneState) -> WorkspacePaneTree {
        guard let root else { return self }
        return WorkspacePaneTree(
            root: root.replacingLeaf(at: path, with: pane),
            zoomedPaneId: zoomedPaneId
        )
    }

    public mutating func resizePane(
        around paneID: String?,
        direction: WorkspacePaneSplitDirection,
        amount: UInt16
    ) {
        guard let paneID, let path = path(to: paneID), let root else {
            return
        }
        guard let ancestorPath = root.nearestSplitPath(for: path, matching: direction.axis) else {
            return
        }
        let delta = min(max(Double(amount) / 100.0, 0.03), 0.25)
        let sign: Double
        switch direction {
        case .left, .top:
            sign = -1
        case .right, .down:
            sign = 1
        }
        self.root = root.adjustingSplitRatio(at: ancestorPath, delta: sign * delta)
    }

    public func focusTarget(from paneID: String?, direction: WorkspacePaneFocusDirection) -> WorkspacePaneState? {
        guard let paneID, let root, let current = root.find(paneID: paneID) else {
            return nil
        }

        switch direction {
        case .previous:
            let allLeaves = root.leaves()
            guard let currentIndex = allLeaves.firstIndex(where: { $0.id == current.id }) else {
                return nil
            }
            let nextIndex = (currentIndex - 1 + allLeaves.count) % allLeaves.count
            return allLeaves[nextIndex]

        case .next:
            let allLeaves = root.leaves()
            guard let currentIndex = allLeaves.firstIndex(where: { $0.id == current.id }) else {
                return nil
            }
            let nextIndex = (currentIndex + 1) % allLeaves.count
            return allLeaves[nextIndex]

        case .left, .right, .top, .down:
            let frames = root.leafFrames(in: CGRect(x: 0, y: 0, width: 1, height: 1))
            guard let currentFrame = frames.first(where: { $0.pane.id == paneID }) else {
                return nil
            }
            let candidates = frames.compactMap { frame -> (WorkspacePaneState, Double, Double, Bool)? in
                guard frame.pane.id != paneID else { return nil }
                switch direction {
                case .left:
                    guard frame.frame.maxX <= currentFrame.frame.minX + 0.0001 else { return nil }
                    return (
                        frame.pane,
                        currentFrame.frame.minX - frame.frame.maxX,
                        abs(frame.frame.midY - currentFrame.frame.midY),
                        frame.frame.maxY > currentFrame.frame.minY && frame.frame.minY < currentFrame.frame.maxY
                    )
                case .right:
                    guard frame.frame.minX >= currentFrame.frame.maxX - 0.0001 else { return nil }
                    return (
                        frame.pane,
                        frame.frame.minX - currentFrame.frame.maxX,
                        abs(frame.frame.midY - currentFrame.frame.midY),
                        frame.frame.maxY > currentFrame.frame.minY && frame.frame.minY < currentFrame.frame.maxY
                    )
                case .top:
                    guard frame.frame.maxY <= currentFrame.frame.minY + 0.0001 else { return nil }
                    return (
                        frame.pane,
                        currentFrame.frame.minY - frame.frame.maxY,
                        abs(frame.frame.midX - currentFrame.frame.midX),
                        frame.frame.maxX > currentFrame.frame.minX && frame.frame.minX < currentFrame.frame.maxX
                    )
                case .down:
                    guard frame.frame.minY >= currentFrame.frame.maxY - 0.0001 else { return nil }
                    return (
                        frame.pane,
                        frame.frame.minY - currentFrame.frame.maxY,
                        abs(frame.frame.midX - currentFrame.frame.midX),
                        frame.frame.maxX > currentFrame.frame.minX && frame.frame.minX < currentFrame.frame.maxX
                    )
                default:
                    return nil
                }
            }
            return candidates.sorted {
                if $0.3 != $1.3 {
                    return $0.3 && !$1.3
                }
                if abs($0.1 - $1.1) > 0.0001 {
                    return $0.1 < $1.1
                }
                return $0.2 < $1.2
            }.first?.0
        }
    }

    public func focusTargetAfterClosing(_ paneID: String?) -> WorkspacePaneState? {
        guard let paneID, let root, let current = root.find(paneID: paneID) else {
            return nil
        }
        let allLeaves = root.leaves()
        guard let currentIndex = allLeaves.firstIndex(where: { $0.id == current.id }) else {
            return nil
        }
        if currentIndex == 0 {
            guard allLeaves.count > 1 else { return nil }
            return allLeaves[1]
        }
        return allLeaves[currentIndex - 1]
    }
}

extension WorkspacePaneTree.Node {
    public var structuralIdentity: StructuralIdentity {
        StructuralIdentity(self)
    }

    public struct StructuralIdentity: Hashable, Sendable {
        private let node: WorkspacePaneTree.Node

        init(_ node: WorkspacePaneTree.Node) {
            self.node = node
        }

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.node.isStructurallyEqual(to: rhs.node)
        }

        public func hash(into hasher: inout Hasher) {
            node.hashStructure(into: &hasher)
        }
    }

    fileprivate func isStructurallyEqual(to other: WorkspacePaneTree.Node) -> Bool {
        switch (self, other) {
        case let (.leaf(leftPane), .leaf(rightPane)):
            return leftPane.id == rightPane.id
        case let (.split(leftSplit), .split(rightSplit)):
            return leftSplit.direction == rightSplit.direction
                && leftSplit.left.isStructurallyEqual(to: rightSplit.left)
                && leftSplit.right.isStructurallyEqual(to: rightSplit.right)
        default:
            return false
        }
    }

    fileprivate func hashStructure(into hasher: inout Hasher) {
        switch self {
        case let .leaf(pane):
            hasher.combine(0)
            hasher.combine(pane.id)
        case let .split(split):
            hasher.combine(1)
            hasher.combine(split.direction)
            split.left.hashStructure(into: &hasher)
            split.right.hashStructure(into: &hasher)
        }
    }

    func leaves() -> [WorkspacePaneState] {
        switch self {
        case let .leaf(pane):
            return [pane]
        case let .split(split):
            return split.left.leaves() + split.right.leaves()
        }
    }

    func find(paneID: String) -> WorkspacePaneState? {
        switch self {
        case let .leaf(pane):
            return pane.id == paneID ? pane : nil
        case let .split(split):
            return split.left.find(paneID: paneID) ?? split.right.find(paneID: paneID)
        }
    }

    func path(to paneID: String) -> WorkspacePaneTree.Path? {
        switch self {
        case let .leaf(pane):
            return pane.id == paneID ? WorkspacePaneTree.Path(components: []) : nil
        case let .split(split):
            if let leftPath = split.left.path(to: paneID) {
                return WorkspacePaneTree.Path(components: [.left] + leftPath.components)
            }
            if let rightPath = split.right.path(to: paneID) {
                return WorkspacePaneTree.Path(components: [.right] + rightPath.components)
            }
            return nil
        }
    }

    func inserting(
        pane: WorkspacePaneState,
        at path: WorkspacePaneTree.Path,
        direction: WorkspacePaneSplitDirection
    ) -> WorkspacePaneTree.Node {
        if path.isEmpty {
            let newLeaf = WorkspacePaneTree.Node.leaf(pane)
            switch direction {
            case .left:
                return .split(
                    WorkspaceSplitState(
                        direction: .horizontal,
                        ratio: 0.5,
                        left: newLeaf,
                        right: self
                    )
                )
            case .right:
                return .split(
                    WorkspaceSplitState(
                        direction: .horizontal,
                        ratio: 0.5,
                        left: self,
                        right: newLeaf
                    )
                )
            case .top:
                return .split(
                    WorkspaceSplitState(
                        direction: .vertical,
                        ratio: 0.5,
                        left: newLeaf,
                        right: self
                    )
                )
            case .down:
                return .split(
                    WorkspaceSplitState(
                        direction: .vertical,
                        ratio: 0.5,
                        left: self,
                        right: newLeaf
                    )
                )
            }
        }

        switch self {
        case .leaf:
            return self
        case let .split(split):
            var remaining = path.components
            let first = remaining.removeFirst()
            let remainingPath = WorkspacePaneTree.Path(components: remaining)
            switch first {
            case .left:
                return .split(
                    WorkspaceSplitState(
                        direction: split.direction,
                        ratio: split.ratio,
                        left: split.left.inserting(pane: pane, at: remainingPath, direction: direction),
                        right: split.right
                    )
                )
            case .right:
                return .split(
                    WorkspaceSplitState(
                        direction: split.direction,
                        ratio: split.ratio,
                        left: split.left,
                        right: split.right.inserting(pane: pane, at: remainingPath, direction: direction)
                    )
                )
            }
        }
    }

    func removing(paneID: String) -> WorkspacePaneTree.Node? {
        switch self {
        case let .leaf(pane):
            return pane.id == paneID ? nil : self
        case let .split(split):
            let left = split.left.removing(paneID: paneID)
            let right = split.right.removing(paneID: paneID)
            switch (left, right) {
            case let (left?, right?):
                return .split(
                    WorkspaceSplitState(
                        direction: split.direction,
                        ratio: split.ratio,
                        left: left,
                        right: right
                    )
                )
            case let (left?, nil):
                return left
            case let (nil, right?):
                return right
            case (nil, nil):
                return nil
            }
        }
    }

    func equalized() -> WorkspacePaneTree.Node {
        switch self {
        case .leaf:
            return self
        case let .split(split):
            return .split(
                WorkspaceSplitState(
                    direction: split.direction,
                    ratio: 0.5,
                    left: split.left.equalized(),
                    right: split.right.equalized()
                )
            )
        }
    }

    func settingSplitRatio(at path: WorkspacePaneTree.Path, ratio: Double) -> WorkspacePaneTree.Node {
        guard !path.isEmpty else {
            switch self {
            case .leaf:
                return self
            case let .split(split):
                return .split(
                    WorkspaceSplitState(
                        direction: split.direction,
                        ratio: ratio,
                        left: split.left,
                        right: split.right
                    )
                )
            }
        }

        switch self {
        case .leaf:
            return self
        case let .split(split):
            var remaining = path.components
            let first = remaining.removeFirst()
            let remainingPath = WorkspacePaneTree.Path(components: remaining)
            switch first {
            case .left:
                return .split(
                    WorkspaceSplitState(
                        direction: split.direction,
                        ratio: split.ratio,
                        left: split.left.settingSplitRatio(at: remainingPath, ratio: ratio),
                        right: split.right
                    )
                )
            case .right:
                return .split(
                    WorkspaceSplitState(
                        direction: split.direction,
                        ratio: split.ratio,
                        left: split.left,
                        right: split.right.settingSplitRatio(at: remainingPath, ratio: ratio)
                    )
                )
            }
        }
    }

    func nearestSplitPath(
        for path: WorkspacePaneTree.Path,
        matching axis: WorkspaceSplitAxis
    ) -> WorkspacePaneTree.Path? {
        var components = path.components
        while true {
            let candidate = WorkspacePaneTree.Path(components: components)
            guard let node = node(at: candidate) else {
                return nil
            }
            if case let .split(split) = node, split.direction == axis {
                return candidate
            }
            guard !components.isEmpty else {
                return nil
            }
            components.removeLast()
        }
    }

    func adjustingSplitRatio(at path: WorkspacePaneTree.Path, delta: Double) -> WorkspacePaneTree.Node {
        guard !path.isEmpty else {
            switch self {
            case .leaf:
                return self
            case let .split(split):
                return .split(
                    WorkspaceSplitState(
                        direction: split.direction,
                        ratio: min(max(split.ratio + delta, 0.1), 0.9),
                        left: split.left,
                        right: split.right
                    )
                )
            }
        }

        switch self {
        case .leaf:
            return self
        case let .split(split):
            var remaining = path.components
            let first = remaining.removeFirst()
            let remainingPath = WorkspacePaneTree.Path(components: remaining)
            switch first {
            case .left:
                return .split(
                    WorkspaceSplitState(
                        direction: split.direction,
                        ratio: split.ratio,
                        left: split.left.adjustingSplitRatio(at: remainingPath, delta: delta),
                        right: split.right
                    )
                )
            case .right:
                return .split(
                    WorkspaceSplitState(
                        direction: split.direction,
                        ratio: split.ratio,
                        left: split.left,
                        right: split.right.adjustingSplitRatio(at: remainingPath, delta: delta)
                    )
                )
            }
        }
    }

    func node(at path: WorkspacePaneTree.Path) -> WorkspacePaneTree.Node? {
        guard !path.isEmpty else { return self }
        switch self {
        case .leaf:
            return nil
        case let .split(split):
            var remaining = path.components
            let first = remaining.removeFirst()
            let remainingPath = WorkspacePaneTree.Path(components: remaining)
            switch first {
            case .left:
                return split.left.node(at: remainingPath)
            case .right:
                return split.right.node(at: remainingPath)
            }
        }
    }

    var leafValue: WorkspacePaneState? {
        guard case let .leaf(pane) = self else {
            return nil
        }
        return pane
    }

    func replacingLeaf(
        at path: WorkspacePaneTree.Path,
        with pane: WorkspacePaneState
    ) -> WorkspacePaneTree.Node {
        guard !path.isEmpty else {
            return .leaf(pane)
        }
        switch self {
        case .leaf:
            return self
        case let .split(split):
            var remaining = path.components
            let first = remaining.removeFirst()
            let remainingPath = WorkspacePaneTree.Path(components: remaining)
            switch first {
            case .left:
                return .split(
                    WorkspaceSplitState(
                        direction: split.direction,
                        ratio: split.ratio,
                        left: split.left.replacingLeaf(at: remainingPath, with: pane),
                        right: split.right
                    )
                )
            case .right:
                return .split(
                    WorkspaceSplitState(
                        direction: split.direction,
                        ratio: split.ratio,
                        left: split.left,
                        right: split.right.replacingLeaf(at: remainingPath, with: pane)
                    )
                )
            }
        }
    }

    public func leafFrames(in frame: CGRect) -> [WorkspacePaneTree.LeafFrame] {
        switch self {
        case let .leaf(pane):
            return [WorkspacePaneTree.LeafFrame(pane: pane, frame: frame)]
        case let .split(split):
            switch split.direction {
            case .horizontal:
                let leftWidth = frame.width * split.ratio
                let leftFrame = CGRect(x: frame.minX, y: frame.minY, width: leftWidth, height: frame.height)
                let rightFrame = CGRect(x: frame.minX + leftWidth, y: frame.minY, width: frame.width - leftWidth, height: frame.height)
                return split.left.leafFrames(in: leftFrame) + split.right.leafFrames(in: rightFrame)
            case .vertical:
                let topHeight = frame.height * split.ratio
                let topFrame = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: topHeight)
                let bottomFrame = CGRect(x: frame.minX, y: frame.minY + topHeight, width: frame.width, height: frame.height - topHeight)
                return split.left.leafFrames(in: topFrame) + split.right.leafFrames(in: bottomFrame)
            }
        }
    }

    public func splitHandles(
        in frame: CGRect,
        path: WorkspacePaneTree.Path,
        splitterVisibleSize: CGFloat = 1,
        splitterInvisibleSize: CGFloat = 6
    ) -> [WorkspacePaneTree.SplitHandle] {
        switch self {
        case .leaf:
            return []
        case let .split(split):
            let handle = WorkspacePaneTree.SplitHandle(
                path: path,
                direction: split.direction,
                splitBounds: frame,
                visibleFrame: WorkspacePaneTree.visibleDividerFrame(
                    in: frame,
                    direction: split.direction,
                    ratio: split.ratio,
                    visibleSize: splitterVisibleSize
                ),
                hitFrame: WorkspacePaneTree.hitDividerFrame(
                    in: frame,
                    direction: split.direction,
                    ratio: split.ratio,
                    visibleSize: splitterVisibleSize,
                    invisibleSize: splitterInvisibleSize
                )
            )

            switch split.direction {
            case .horizontal:
                let leftWidth = frame.width * split.ratio
                let leftFrame = CGRect(x: frame.minX, y: frame.minY, width: leftWidth, height: frame.height)
                let rightFrame = CGRect(x: frame.minX + leftWidth, y: frame.minY, width: frame.width - leftWidth, height: frame.height)
                return [handle]
                    + split.left.splitHandles(
                        in: leftFrame,
                        path: path.appending(.left),
                        splitterVisibleSize: splitterVisibleSize,
                        splitterInvisibleSize: splitterInvisibleSize
                    )
                    + split.right.splitHandles(
                        in: rightFrame,
                        path: path.appending(.right),
                        splitterVisibleSize: splitterVisibleSize,
                        splitterInvisibleSize: splitterInvisibleSize
                    )
            case .vertical:
                let topHeight = frame.height * split.ratio
                let topFrame = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: topHeight)
                let bottomFrame = CGRect(x: frame.minX, y: frame.minY + topHeight, width: frame.width, height: frame.height - topHeight)
                return [handle]
                    + split.left.splitHandles(
                        in: topFrame,
                        path: path.appending(.left),
                        splitterVisibleSize: splitterVisibleSize,
                        splitterInvisibleSize: splitterInvisibleSize
                    )
                    + split.right.splitHandles(
                        in: bottomFrame,
                        path: path.appending(.right),
                        splitterVisibleSize: splitterVisibleSize,
                        splitterInvisibleSize: splitterInvisibleSize
                    )
            }
        }
    }
}

private extension WorkspacePaneTree {
    static func dividerPosition(
        in frame: CGRect,
        direction: WorkspaceSplitAxis,
        ratio: Double,
        visibleSize: CGFloat
    ) -> CGFloat {
        switch direction {
        case .horizontal:
            return frame.minX + (frame.width * ratio) - (visibleSize / 2)
        case .vertical:
            return frame.minY + (frame.height * ratio) - (visibleSize / 2)
        }
    }

    static func visibleDividerFrame(
        in frame: CGRect,
        direction: WorkspaceSplitAxis,
        ratio: Double,
        visibleSize: CGFloat
    ) -> CGRect {
        switch direction {
        case .horizontal:
            let x = dividerPosition(in: frame, direction: direction, ratio: ratio, visibleSize: visibleSize)
            return CGRect(x: x, y: frame.minY, width: visibleSize, height: frame.height)
        case .vertical:
            let y = dividerPosition(in: frame, direction: direction, ratio: ratio, visibleSize: visibleSize)
            return CGRect(x: frame.minX, y: y, width: frame.width, height: visibleSize)
        }
    }

    static func hitDividerFrame(
        in frame: CGRect,
        direction: WorkspaceSplitAxis,
        ratio: Double,
        visibleSize: CGFloat,
        invisibleSize: CGFloat
    ) -> CGRect {
        let visibleFrame = visibleDividerFrame(in: frame, direction: direction, ratio: ratio, visibleSize: visibleSize)
        switch direction {
        case .horizontal:
            return visibleFrame.insetBy(dx: -invisibleSize / 2, dy: 0)
        case .vertical:
            return visibleFrame.insetBy(dx: 0, dy: -invisibleSize / 2)
        }
    }
}

public struct WorkspaceTabState: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var tree: WorkspacePaneTree
    public var focusedPaneId: String

    public init(id: String, title: String, tree: WorkspacePaneTree, focusedPaneId: String) {
        self.id = id
        self.title = title
        self.tree = tree
        self.focusedPaneId = focusedPaneId
    }

    public var leaves: [WorkspacePaneState] {
        tree.leaves
    }

    public var rootSplit: WorkspaceSplitState? {
        tree.rootSplit
    }
}

public struct WorkspaceSessionState: Equatable, Sendable {
    public var workspaceId: String
    public var projectPath: String
    public private(set) var tabs: [WorkspaceTabState]
    public private(set) var selectedTabId: String?

    private var nextTabNumber: Int
    private var nextPaneNumber: Int

    public init(
        projectPath: String,
        workspaceId: String = "workspace:\(UUID().uuidString.lowercased())"
    ) {
        self.init(
            projectPath: projectPath,
            workspaceId: workspaceId,
            tabs: [],
            selectedTabId: nil,
            nextTabNumber: 1,
            nextPaneNumber: 1
        )
        _ = createTab()
    }

    init(
        projectPath: String,
        workspaceId: String,
        tabs: [WorkspaceTabState],
        selectedTabId: String?,
        nextTabNumber: Int,
        nextPaneNumber: Int
    ) {
        self.workspaceId = workspaceId
        self.projectPath = projectPath
        self.tabs = tabs
        self.selectedTabId = selectedTabId
        self.nextTabNumber = max(nextTabNumber, 1)
        self.nextPaneNumber = max(nextPaneNumber, 1)
    }

    public var selectedTab: WorkspaceTabState? {
        guard let selectedTabId else { return tabs.first }
        return tabs.first(where: { $0.id == selectedTabId }) ?? tabs.first
    }

    public var selectedPane: WorkspacePaneState? {
        guard let selectedTab else { return nil }
        return selectedTab.tree.find(paneID: selectedTab.focusedPaneId) ?? selectedTab.leaves.first
    }

    public var selectedPaneItem: WorkspacePaneItemState? {
        selectedPane?.selectedItem
    }

    @discardableResult
    public mutating func createTab() -> WorkspaceTabState {
        let tabNumber = nextTabNumber
        nextTabNumber += 1

        let tabID = "\(workspaceId)/tab:\(tabNumber)"
        let pane = makePane(for: tabID)
        let tree = WorkspacePaneTree(root: .leaf(pane), zoomedPaneId: nil)
        let tab = WorkspaceTabState(
            id: tabID,
            title: WorkspaceTabTitlePolicy.defaultTitle(for: tabNumber),
            tree: tree,
            focusedPaneId: pane.id
        )

        if let selectedTabId,
           let selectedIndex = tabs.firstIndex(where: { $0.id == selectedTabId }) {
            tabs.insert(tab, at: selectedIndex + 1)
        } else {
            tabs.append(tab)
        }
        self.selectedTabId = tab.id
        return tab
    }

    public mutating func selectTab(_ tabID: String?) {
        guard let tabID, tabs.contains(where: { $0.id == tabID }) else {
            return
        }
        selectedTabId = tabID
    }

    public mutating func gotoPreviousTab() {
        guard !tabs.isEmpty else { return }
        let index = selectedTabIndex ?? 0
        let previousIndex = (index - 1 + tabs.count) % tabs.count
        selectedTabId = tabs[previousIndex].id
    }

    public mutating func gotoNextTab() {
        guard !tabs.isEmpty else { return }
        let index = selectedTabIndex ?? 0
        let nextIndex = (index + 1) % tabs.count
        selectedTabId = tabs[nextIndex].id
    }

    public mutating func gotoLastTab() {
        guard let last = tabs.last else { return }
        selectedTabId = last.id
    }

    public mutating func gotoTab(at index: Int) {
        guard !tabs.isEmpty else { return }
        let clamped = min(max(index - 1, 0), tabs.count - 1)
        selectedTabId = tabs[clamped].id
    }

    public mutating func moveSelectedTab(by amount: Int) {
        guard let selectedTabId else { return }
        moveTab(id: selectedTabId, by: amount)
    }

    public mutating func moveTab(id: String, by amount: Int) {
        guard let currentIndex = tabs.firstIndex(where: { $0.id == id }) else { return }
        let targetIndex = min(max(currentIndex + amount, 0), tabs.count - 1)
        guard targetIndex != currentIndex else { return }
        let tab = tabs.remove(at: currentIndex)
        tabs.insert(tab, at: targetIndex)
        selectedTabId = id
    }

    public mutating func closeTab(_ id: String) {
        closeTab(id, allowsEmptyTabs: false)
    }

    public mutating func closeTabAllowingEmpty(_ id: String) {
        closeTab(id, allowsEmptyTabs: true)
    }

    private mutating func closeTab(_ id: String, allowsEmptyTabs: Bool) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)

        if tabs.isEmpty {
            if allowsEmptyTabs {
                selectedTabId = nil
            } else {
                _ = createTab()
            }
            return
        }

        if selectedTabId == id {
            let nextIndex = max(0, index - 1)
            selectedTabId = tabs[nextIndex].id
        } else if selectedTabId == nil {
            selectedTabId = tabs.first?.id
        }
    }

    public mutating func closeOtherTabs(keeping id: String) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        tabs = tabs.filter { $0.id == id }
        selectedTabId = id
    }

    public mutating func closeTabsToRight(of id: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs = Array(tabs.prefix(index + 1))
        selectedTabId = tabs.contains(where: { $0.id == selectedTabId }) ? selectedTabId : tabs.last?.id
        if tabs.isEmpty {
            _ = createTab()
        }
    }

    @discardableResult
    public mutating func splitFocusedPane(direction: WorkspacePaneSplitDirection) -> WorkspacePaneState? {
        guard let tabIndex = selectedTabIndex else { return nil }
        let anchorPaneID = tabs[tabIndex].focusedPaneId
        let newPane = makePane(for: tabs[tabIndex].id)
        guard tabs[tabIndex].tree.insertPane(newPane, at: anchorPaneID, direction: direction) else {
            return nil
        }
        tabs[tabIndex].focusedPaneId = newPane.id
        return newPane
    }

    @discardableResult
    public mutating func createTerminalItem(inPane paneID: String?) -> WorkspacePaneItemState? {
        guard let paneID else { return nil }
        guard let tabIndex = tabs.firstIndex(where: { $0.tree.find(paneID: paneID) != nil }) else {
            return nil
        }
        guard let panePath = tabs[tabIndex].tree.path(to: paneID),
              var pane = tabs[tabIndex].tree.node(at: panePath)?.leafValue else {
            return nil
        }
        let item = makePaneItem(for: tabs[tabIndex].id, inPane: paneID)
        pane.appendItem(item)
        tabs[tabIndex].tree = tabs[tabIndex].tree.replacingPane(at: panePath, with: pane)
        tabs[tabIndex].focusedPaneId = paneID
        selectedTabId = tabs[tabIndex].id
        return item
    }

    @discardableResult
    public mutating func createBrowserItem(
        inPane paneID: String?,
        urlString: String? = nil
    ) -> WorkspacePaneItemState? {
        guard let paneID else { return nil }
        guard let tabIndex = tabs.firstIndex(where: { $0.tree.find(paneID: paneID) != nil }) else {
            return nil
        }
        guard let panePath = tabs[tabIndex].tree.path(to: paneID),
              var pane = tabs[tabIndex].tree.node(at: panePath)?.leafValue else {
            return nil
        }
        let item = makeBrowserItem(
            for: tabs[tabIndex].id,
            inPane: paneID,
            urlString: urlString
        )
        pane.appendItem(item)
        tabs[tabIndex].tree = tabs[tabIndex].tree.replacingPane(at: panePath, with: pane)
        tabs[tabIndex].focusedPaneId = paneID
        selectedTabId = tabs[tabIndex].id
        return item
    }

    public mutating func selectPaneItem(paneID: String?, itemID: String?) {
        guard let paneID, let itemID else { return }
        guard let tabIndex = tabs.firstIndex(where: { $0.tree.find(paneID: paneID) != nil }) else {
            return
        }
        guard let panePath = tabs[tabIndex].tree.path(to: paneID),
              var pane = tabs[tabIndex].tree.node(at: panePath)?.leafValue else {
            return
        }
        guard pane.items.contains(where: { $0.id == itemID }) else {
            return
        }
        pane.selectItem(itemID)
        tabs[tabIndex].tree = tabs[tabIndex].tree.replacingPane(at: panePath, with: pane)
        tabs[tabIndex].focusedPaneId = paneID
        selectedTabId = tabs[tabIndex].id
    }

    public mutating func gotoPreviousPaneItem(inPane paneID: String?) {
        guard let paneID else { return }
        guard let tabIndex = tabs.firstIndex(where: { $0.tree.find(paneID: paneID) != nil }) else {
            return
        }
        guard let panePath = tabs[tabIndex].tree.path(to: paneID),
              var pane = tabs[tabIndex].tree.node(at: panePath)?.leafValue,
              !pane.items.isEmpty
        else {
            return
        }
        let currentIndex = pane.selectedIndex ?? 0
        let previousIndex = (currentIndex - 1 + pane.items.count) % pane.items.count
        pane.selectItem(pane.items[previousIndex].id)
        tabs[tabIndex].tree = tabs[tabIndex].tree.replacingPane(at: panePath, with: pane)
        tabs[tabIndex].focusedPaneId = paneID
        selectedTabId = tabs[tabIndex].id
    }

    public mutating func gotoNextPaneItem(inPane paneID: String?) {
        guard let paneID else { return }
        guard let tabIndex = tabs.firstIndex(where: { $0.tree.find(paneID: paneID) != nil }) else {
            return
        }
        guard let panePath = tabs[tabIndex].tree.path(to: paneID),
              var pane = tabs[tabIndex].tree.node(at: panePath)?.leafValue,
              !pane.items.isEmpty
        else {
            return
        }
        let currentIndex = pane.selectedIndex ?? 0
        let nextIndex = (currentIndex + 1) % pane.items.count
        pane.selectItem(pane.items[nextIndex].id)
        tabs[tabIndex].tree = tabs[tabIndex].tree.replacingPane(at: panePath, with: pane)
        tabs[tabIndex].focusedPaneId = paneID
        selectedTabId = tabs[tabIndex].id
    }

    public mutating func gotoLastPaneItem(inPane paneID: String?) {
        guard let paneID else { return }
        guard let tabIndex = tabs.firstIndex(where: { $0.tree.find(paneID: paneID) != nil }) else {
            return
        }
        guard let panePath = tabs[tabIndex].tree.path(to: paneID),
              var pane = tabs[tabIndex].tree.node(at: panePath)?.leafValue,
              let last = pane.items.last
        else {
            return
        }
        pane.selectItem(last.id)
        tabs[tabIndex].tree = tabs[tabIndex].tree.replacingPane(at: panePath, with: pane)
        tabs[tabIndex].focusedPaneId = paneID
        selectedTabId = tabs[tabIndex].id
    }

    public mutating func gotoPaneItem(at index: Int, inPane paneID: String?) {
        guard let paneID else { return }
        guard let tabIndex = tabs.firstIndex(where: { $0.tree.find(paneID: paneID) != nil }) else {
            return
        }
        guard let panePath = tabs[tabIndex].tree.path(to: paneID),
              var pane = tabs[tabIndex].tree.node(at: panePath)?.leafValue,
              !pane.items.isEmpty
        else {
            return
        }
        let clampedIndex = min(max(index - 1, 0), pane.items.count - 1)
        pane.selectItem(pane.items[clampedIndex].id)
        tabs[tabIndex].tree = tabs[tabIndex].tree.replacingPane(at: panePath, with: pane)
        tabs[tabIndex].focusedPaneId = paneID
        selectedTabId = tabs[tabIndex].id
    }

    public mutating func movePaneItem(
        inPane paneID: String?,
        itemID: String?,
        by amount: Int
    ) {
        guard let paneID, let itemID, amount != 0 else { return }
        guard let tabIndex = tabs.firstIndex(where: { $0.tree.find(paneID: paneID) != nil }) else {
            return
        }
        guard let panePath = tabs[tabIndex].tree.path(to: paneID),
              var pane = tabs[tabIndex].tree.node(at: panePath)?.leafValue else {
            return
        }
        pane.moveItem(id: itemID, by: amount)
        tabs[tabIndex].tree = tabs[tabIndex].tree.replacingPane(at: panePath, with: pane)
        tabs[tabIndex].focusedPaneId = paneID
        selectedTabId = tabs[tabIndex].id
    }

    @discardableResult
    public mutating func movePaneItem(
        _ itemID: String?,
        from sourcePaneID: String?,
        to targetPaneID: String?,
        at targetIndex: Int? = nil
    ) -> WorkspacePaneItemState? {
        guard let itemID, let sourcePaneID, let targetPaneID else {
            return nil
        }
        guard let tabIndex = tabs.firstIndex(where: {
            $0.tree.find(paneID: sourcePaneID) != nil && $0.tree.find(paneID: targetPaneID) != nil
        }) else {
            return nil
        }

        if sourcePaneID == targetPaneID {
            guard let panePath = tabs[tabIndex].tree.path(to: sourcePaneID),
                  var pane = tabs[tabIndex].tree.node(at: panePath)?.leafValue,
                  let movingItem = pane.removeItem(id: itemID)
            else {
                return nil
            }
            pane.insertItem(movingItem, at: targetIndex)
            tabs[tabIndex].tree = tabs[tabIndex].tree.replacingPane(at: panePath, with: pane)
            tabs[tabIndex].focusedPaneId = sourcePaneID
            selectedTabId = tabs[tabIndex].id
            return movingItem
        }

        var tree = tabs[tabIndex].tree
        guard let sourcePanePath = tree.path(to: sourcePaneID),
              var sourcePane = tree.node(at: sourcePanePath)?.leafValue,
              let movingItem = sourcePane.removeItem(id: itemID)
        else {
            return nil
        }

        if sourcePane.items.isEmpty {
            guard tree.removePane(sourcePaneID) else {
                return nil
            }
        } else {
            tree = tree.replacingPane(at: sourcePanePath, with: sourcePane)
        }

        guard let targetPanePath = tree.path(to: targetPaneID),
              var targetPane = tree.node(at: targetPanePath)?.leafValue
        else {
            return nil
        }

        let reboundItem = movingItem.rebinding(tabId: tabs[tabIndex].id, paneId: targetPaneID)
        targetPane.insertItem(reboundItem, at: targetIndex)
        tree = tree.replacingPane(at: targetPanePath, with: targetPane)

        tabs[tabIndex].tree = tree
        tabs[tabIndex].focusedPaneId = targetPaneID
        selectedTabId = tabs[tabIndex].id
        return reboundItem
    }

    @discardableResult
    public mutating func splitPaneItem(
        _ itemID: String?,
        from sourcePaneID: String?,
        beside anchorPaneID: String?,
        direction: WorkspacePaneSplitDirection
    ) -> WorkspacePaneState? {
        guard let itemID, let sourcePaneID, let anchorPaneID else {
            return nil
        }
        guard let tabIndex = tabs.firstIndex(where: {
            $0.tree.find(paneID: sourcePaneID) != nil && $0.tree.find(paneID: anchorPaneID) != nil
        }) else {
            return nil
        }

        let tabID = tabs[tabIndex].id
        let nextPaneSequence = nextPaneNumber
        let newPaneID = "\(workspaceId)/pane:\(nextPaneSequence)"

        var tree = tabs[tabIndex].tree
        guard let sourcePanePath = tree.path(to: sourcePaneID),
              var sourcePane = tree.node(at: sourcePanePath)?.leafValue,
              let movingItem = sourcePane.removeItem(id: itemID)
        else {
            return nil
        }

        if sourcePane.items.isEmpty {
            guard sourcePaneID != anchorPaneID else {
                return nil
            }
            guard tree.removePane(sourcePaneID) else {
                return nil
            }
        } else {
            tree = tree.replacingPane(at: sourcePanePath, with: sourcePane)
        }

        let reboundItem = movingItem.rebinding(tabId: tabID, paneId: newPaneID)
        let newPane = WorkspacePaneState(
            paneId: newPaneID,
            items: [reboundItem],
            selectedItemId: reboundItem.id
        )
        guard tree.insertPane(newPane, at: anchorPaneID, direction: direction) else {
            return nil
        }

        nextPaneNumber += 1
        tabs[tabIndex].tree = tree
        tabs[tabIndex].focusedPaneId = newPaneID
        selectedTabId = tabID
        return newPane
    }

    public mutating func movePane(
        _ paneID: String?,
        beside targetPaneID: String?,
        direction: WorkspacePaneSplitDirection
    ) {
        guard let paneID, let targetPaneID, paneID != targetPaneID else {
            return
        }
        guard let tabIndex = tabs.firstIndex(where: {
            $0.tree.find(paneID: paneID) != nil && $0.tree.find(paneID: targetPaneID) != nil
        }) else {
            return
        }
        guard let movingPane = tabs[tabIndex].tree.find(paneID: paneID) else {
            return
        }

        var tree = tabs[tabIndex].tree
        guard tree.removePane(paneID) else {
            return
        }
        guard tree.insertPane(movingPane, at: targetPaneID, direction: direction) else {
            return
        }

        tabs[tabIndex].tree = tree
        tabs[tabIndex].focusedPaneId = movingPane.id
        selectedTabId = tabs[tabIndex].id
    }

    public mutating func closeOtherPaneItems(
        inPane paneID: String?,
        keeping itemID: String?
    ) {
        guard let paneID, let itemID else { return }
        guard let tabIndex = tabs.firstIndex(where: { $0.tree.find(paneID: paneID) != nil }) else {
            return
        }
        guard let panePath = tabs[tabIndex].tree.path(to: paneID),
              var pane = tabs[tabIndex].tree.node(at: panePath)?.leafValue else {
            return
        }
        pane.closeOtherItems(keeping: itemID)
        tabs[tabIndex].tree = tabs[tabIndex].tree.replacingPane(at: panePath, with: pane)
        tabs[tabIndex].focusedPaneId = paneID
        selectedTabId = tabs[tabIndex].id
    }

    public mutating func closePaneItemsToRight(
        inPane paneID: String?,
        of itemID: String?
    ) {
        guard let paneID, let itemID else { return }
        guard let tabIndex = tabs.firstIndex(where: { $0.tree.find(paneID: paneID) != nil }) else {
            return
        }
        guard let panePath = tabs[tabIndex].tree.path(to: paneID),
              var pane = tabs[tabIndex].tree.node(at: panePath)?.leafValue else {
            return
        }
        pane.closeItemsToRight(of: itemID)
        tabs[tabIndex].tree = tabs[tabIndex].tree.replacingPane(at: panePath, with: pane)
        tabs[tabIndex].focusedPaneId = paneID
        selectedTabId = tabs[tabIndex].id
    }

    public mutating func closePaneItem(paneID: String?, itemID: String?) {
        guard let paneID, let itemID else { return }
        guard let tabIndex = tabs.firstIndex(where: { $0.tree.find(paneID: paneID) != nil }) else {
            return
        }
        guard let panePath = tabs[tabIndex].tree.path(to: paneID),
              var pane = tabs[tabIndex].tree.node(at: panePath)?.leafValue else {
            return
        }
        guard pane.items.contains(where: { $0.id == itemID }) else {
            return
        }
        if pane.items.count <= 1 {
            closePane(paneID)
            return
        }
        _ = pane.removeItem(id: itemID)
        tabs[tabIndex].tree = tabs[tabIndex].tree.replacingPane(at: panePath, with: pane)
        tabs[tabIndex].focusedPaneId = paneID
        selectedTabId = tabs[tabIndex].id
    }

    public mutating func focusPane(_ paneID: String?) {
        guard let paneID else { return }
        guard let tabIndex = tabs.firstIndex(where: { $0.tree.find(paneID: paneID) != nil }) else {
            return
        }
        selectedTabId = tabs[tabIndex].id
        tabs[tabIndex].focusedPaneId = paneID
    }

    public mutating func focusPane(direction: WorkspacePaneFocusDirection) {
        guard let tabIndex = selectedTabIndex else { return }
        let currentPaneID = tabs[tabIndex].focusedPaneId
        guard let target = tabs[tabIndex].tree.focusTarget(from: currentPaneID, direction: direction) else {
            return
        }
        tabs[tabIndex].focusedPaneId = target.id
    }

    public mutating func closePane(_ paneID: String?) {
        guard let paneID else { return }
        guard let tabIndex = tabs.firstIndex(where: { $0.tree.find(paneID: paneID) != nil }) else {
            return
        }

        let nextFocus = tabs[tabIndex].tree.focusTargetAfterClosing(paneID)
        let removed = tabs[tabIndex].tree.removePane(paneID)
        guard removed else { return }

        if tabs[tabIndex].tree.isEmpty {
            let closingTabID = tabs[tabIndex].id
            closeTab(closingTabID)
            return
        }

        if tabs[tabIndex].focusedPaneId == paneID {
            tabs[tabIndex].focusedPaneId = nextFocus?.id ?? tabs[tabIndex].leaves.first?.id ?? tabs[tabIndex].focusedPaneId
        }
    }

    public mutating func resizeFocusedPane(direction: WorkspacePaneSplitDirection, amount: UInt16) {
        guard let tabIndex = selectedTabIndex else { return }
        let focusedPaneID = tabs[tabIndex].focusedPaneId
        tabs[tabIndex].tree.resizePane(around: focusedPaneID, direction: direction, amount: amount)
    }

    public mutating func equalizeSelectedTabSplits() {
        guard let tabIndex = selectedTabIndex else { return }
        tabs[tabIndex].tree.equalize()
    }

    public mutating func toggleZoomOnFocusedPane() {
        guard let tabIndex = selectedTabIndex else { return }
        tabs[tabIndex].tree.toggleZoom(on: tabs[tabIndex].focusedPaneId)
    }

    public mutating func setSelectedTabSplitRatio(at path: WorkspacePaneTree.Path, ratio: Double) {
        guard let tabIndex = selectedTabIndex else { return }
        tabs[tabIndex].tree.setSplitRatio(at: path, ratio: ratio)
    }

    public mutating func updateTitle(for tabID: String, title: String) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let resolvedTitle = WorkspaceTabTitlePolicy.resolveRuntimeTitle(
            currentTitle: tabs[index].title,
            runtimeTitle: trimmed
        )
        guard tabs[index].title != resolvedTitle else {
            return
        }
        tabs[index].title = resolvedTitle
    }

    public mutating func updatePaneItemTitle(
        inPane paneID: String?,
        itemID: String?,
        title: String
    ) {
        guard let paneID, let itemID else { return }
        guard let tabIndex = tabs.firstIndex(where: { $0.tree.find(paneID: paneID) != nil }) else {
            return
        }
        guard let panePath = tabs[tabIndex].tree.path(to: paneID),
              var pane = tabs[tabIndex].tree.node(at: panePath)?.leafValue else {
            return
        }
        pane.updateItemTitle(id: itemID, title: title)
        tabs[tabIndex].tree = tabs[tabIndex].tree.replacingPane(at: panePath, with: pane)
    }

    @discardableResult
    public mutating func updateBrowserState(
        inPane paneID: String?,
        itemID: String?,
        title: String? = nil,
        urlString: String? = nil,
        isLoading: Bool? = nil
    ) -> WorkspaceBrowserState? {
        guard let paneID, let itemID else {
            return nil
        }
        guard let tabIndex = tabs.firstIndex(where: { $0.tree.find(paneID: paneID) != nil }) else {
            return nil
        }
        guard let panePath = tabs[tabIndex].tree.path(to: paneID),
              var pane = tabs[tabIndex].tree.node(at: panePath)?.leafValue
        else {
            return nil
        }
        let previousState = pane.items.first(where: { $0.id == itemID })?.browserState
        let nextState = pane.updateBrowserItemState(
            id: itemID,
            title: title,
            urlString: urlString,
            isLoading: isLoading
        )
        guard nextState != previousState else {
            return nextState
        }
        tabs[tabIndex].tree = tabs[tabIndex].tree.replacingPane(at: panePath, with: pane)
        return nextState
    }

    private var selectedTabIndex: Int? {
        guard let selectedTabId else {
            return tabs.isEmpty ? nil : 0
        }
        return tabs.firstIndex(where: { $0.id == selectedTabId })
    }

    private mutating func makePane(for tabID: String) -> WorkspacePaneState {
        let paneNumber = nextPaneNumber
        nextPaneNumber += 1
        let paneID = "\(workspaceId)/pane:\(paneNumber)"
        let item = makePaneItem(for: tabID, inPane: paneID, sequenceNumber: paneNumber)
        return WorkspacePaneState(
            paneId: paneID,
            items: [item],
            selectedItemId: item.id
        )
    }

    private mutating func makePaneItem(
        for tabID: String,
        inPane paneID: String,
        sequenceNumber: Int? = nil
    ) -> WorkspacePaneItemState {
        let itemNumber: Int
        if let sequenceNumber {
            itemNumber = sequenceNumber
        } else {
            itemNumber = nextPaneNumber
            nextPaneNumber += 1
        }
        let request = WorkspaceTerminalLaunchRequest(
            projectPath: projectPath,
            workspaceId: workspaceId,
            tabId: tabID,
            paneId: paneID,
            surfaceId: "\(workspaceId)/surface:\(itemNumber)",
            terminalSessionId: "\(workspaceId)/session:\(itemNumber)"
        )
        return WorkspacePaneItemState(
            request: request,
            title: WorkspaceTabTitlePolicy.defaultTitle(for: itemNumber)
        )
    }

    private mutating func makeBrowserItem(
        for tabID: String,
        inPane paneID: String,
        urlString: String? = nil
    ) -> WorkspacePaneItemState {
        let itemNumber = nextPaneNumber
        nextPaneNumber += 1
        let request = WorkspaceTerminalLaunchRequest(
            projectPath: projectPath,
            workspaceId: workspaceId,
            tabId: tabID,
            paneId: paneID,
            surfaceId: "\(workspaceId)/surface:\(itemNumber)",
            terminalSessionId: "\(workspaceId)/browser-session:\(itemNumber)",
            terminalRuntime: "browser"
        )
        let browserState = WorkspaceBrowserState(
            surfaceId: request.surfaceId,
            projectPath: projectPath,
            tabId: tabID,
            paneId: paneID,
            title: "浏览器",
            urlString: urlString ?? "",
            isLoading: false
        )
        return WorkspacePaneItemState(
            request: request,
            title: browserState.title,
            kind: .browser,
            browserState: browserState
        )
    }

    public init(restoring snapshot: ProjectWorkspaceRestoreSnapshot) {
        let restoredTabs = snapshot.tabs.map { tab in
            WorkspaceTabState(
                id: tab.id,
                title: tab.title,
                tree: WorkspacePaneTree(restoring: tab.tree, projectPath: snapshot.projectPath, workspaceId: snapshot.workspaceId, tabID: tab.id),
                focusedPaneId: tab.focusedPaneId
            )
        }
        let selectedTabId = snapshot.selectedTabId.flatMap { candidate in
            restoredTabs.contains(where: { $0.id == candidate }) ? candidate : nil
        } ?? restoredTabs.first?.id
        self.init(
            projectPath: snapshot.projectPath,
            workspaceId: snapshot.workspaceId,
            tabs: restoredTabs.isEmpty
                ? [WorkspaceSessionState(projectPath: snapshot.projectPath, workspaceId: snapshot.workspaceId).selectedTab!]
                : restoredTabs,
            selectedTabId: selectedTabId,
            nextTabNumber: snapshot.nextTabNumber,
            nextPaneNumber: snapshot.nextPaneNumber
        )
    }

    public func makeRestoreSnapshot(
        rootProjectPath: String,
        isQuickTerminal: Bool,
        workspaceRootContext: WorkspaceRootSessionContext?,
        workspaceAlignmentGroupID: String?
    ) -> ProjectWorkspaceRestoreSnapshot {
        ProjectWorkspaceRestoreSnapshot(
            projectPath: projectPath,
            rootProjectPath: rootProjectPath,
            isQuickTerminal: isQuickTerminal,
            workspaceRootContext: workspaceRootContext,
            workspaceAlignmentGroupID: workspaceAlignmentGroupID,
            workspaceId: workspaceId,
            selectedTabId: selectedTabId,
            nextTabNumber: nextTabNumber,
            nextPaneNumber: nextPaneNumber,
            tabs: tabs.map { tab in
                WorkspaceTabRestoreSnapshot(
                    id: tab.id,
                    title: tab.title,
                    focusedPaneId: tab.focusedPaneId,
                    tree: tab.tree.makeRestoreSnapshot()
                )
            }
        )
    }
}

private extension WorkspacePaneTree {
    init(
        restoring snapshot: WorkspacePaneTreeRestoreSnapshot,
        projectPath: String,
        workspaceId: String,
        tabID: String
    ) {
        self.init(
            root: Self.makeNode(
                from: snapshot.root,
                projectPath: projectPath,
                workspaceId: workspaceId,
                tabID: tabID
            ),
            zoomedPaneId: snapshot.zoomedPaneId
        )
    }

    func makeRestoreSnapshot() -> WorkspacePaneTreeRestoreSnapshot {
        guard let root else {
            preconditionFailure("Workspace tab 缺少 pane tree root，无法导出恢复快照")
        }
        return WorkspacePaneTreeRestoreSnapshot(
            root: root.makeRestoreSnapshot(),
            zoomedPaneId: zoomedPaneId
        )
    }

    static func makeNode(
        from snapshot: WorkspacePaneTreeRestoreSnapshot.Node,
        projectPath: String,
        workspaceId: String,
        tabID: String
    ) -> WorkspacePaneTree.Node {
        switch snapshot {
        case let .leaf(pane):
            return .leaf(
                WorkspacePaneState(
                    paneId: pane.paneId,
                    items: pane.items.map { item in
                        if item.kind == .browser {
                            let browserState = WorkspaceBrowserState(
                                surfaceId: item.surfaceId,
                                projectPath: projectPath,
                                tabId: tabID,
                                paneId: pane.paneId,
                                title: item.browserTitle ?? item.restoredTitle ?? "浏览器",
                                urlString: item.browserURLString ?? "",
                                isLoading: item.browserIsLoading ?? false
                            )
                            return WorkspacePaneItemState(
                                request: WorkspaceTerminalLaunchRequest(
                                    projectPath: projectPath,
                                    workspaceId: workspaceId,
                                    tabId: tabID,
                                    paneId: pane.paneId,
                                    surfaceId: item.surfaceId,
                                    terminalSessionId: item.terminalSessionId,
                                    terminalRuntime: "browser"
                                ),
                                title: browserState.title,
                                kind: .browser,
                                browserState: browserState
                            )
                        }

                        let restoreContext = WorkspaceTerminalRestoreContext(
                            workingDirectory: item.restoredWorkingDirectory,
                            title: item.restoredTitle,
                            snapshotText: item.snapshotText,
                            agentSummary: item.agentSummary
                        )
                        return WorkspacePaneItemState(
                            request: WorkspaceTerminalLaunchRequest(
                                projectPath: projectPath,
                                workspaceId: workspaceId,
                                tabId: tabID,
                                paneId: pane.paneId,
                                surfaceId: item.surfaceId,
                                terminalSessionId: item.terminalSessionId,
                                workingDirectoryOverride: item.restoredWorkingDirectory,
                                restoreContext: restoreContext.isEmpty ? nil : restoreContext
                            ),
                            title: item.restoredTitle ?? WorkspaceTabTitlePolicy.defaultTitle(for: 1)
                        )
                    },
                    selectedItemId: pane.selectedItemId ?? pane.items.last?.surfaceId ?? pane.items.first?.surfaceId ?? ""
                )
            )
        case let .split(split):
            return .split(
                WorkspaceSplitState(
                    direction: split.direction,
                    ratio: split.ratio,
                    left: makeNode(
                        from: split.left,
                        projectPath: projectPath,
                        workspaceId: workspaceId,
                        tabID: tabID
                    ),
                    right: makeNode(
                        from: split.right,
                        projectPath: projectPath,
                        workspaceId: workspaceId,
                        tabID: tabID
                    )
                )
            )
        }
    }
}

private extension WorkspacePaneTree.Node {
    func makeRestoreSnapshot() -> WorkspacePaneTreeRestoreSnapshot.Node {
        switch self {
        case let .leaf(pane):
            return .leaf(
                WorkspacePaneRestoreSnapshot(
                    paneId: pane.id,
                    selectedItemId: pane.selectedItemId,
                    items: pane.items.map { item in
                        WorkspacePaneItemRestoreSnapshot(
                            surfaceId: item.request.surfaceId,
                            terminalSessionId: item.request.terminalSessionId,
                            kind: item.kind,
                            restoredWorkingDirectory: item.request.restoreContext?.workingDirectory,
                            restoredTitle: item.title,
                            agentSummary: item.request.restoreContext?.agentSummary,
                            snapshotTextRef: nil,
                            snapshotText: item.request.restoreContext?.snapshotText,
                            browserTitle: item.browserState?.title,
                            browserURLString: item.browserState?.urlString,
                            browserIsLoading: item.browserState?.isLoading
                        )
                    }
                )
            )
        case let .split(split):
            return .split(
                WorkspaceSplitRestoreSnapshot(
                    direction: split.direction,
                    ratio: split.ratio,
                    left: split.left.makeRestoreSnapshot(),
                    right: split.right.makeRestoreSnapshot()
                )
            )
        }
    }
}
