import SwiftUI
import GhosttyKit
import DevHavenCore

struct WorkspaceSplitTreeView: View {
    fileprivate static let canvasCoordinateSpaceName = "workspace-split-tree-canvas"

    let tab: WorkspaceTabState
    let isTabSelected: Bool
    let surfaceModelForPaneItem: (WorkspacePaneState, WorkspacePaneItemState) -> GhosttySurfaceHostModel
    let browserModelForPaneItem: (WorkspacePaneState, WorkspacePaneItemState) -> WorkspaceBrowserHostModel?
    let surfaceActivityForPaneItem: (WorkspacePaneState, WorkspacePaneItemState) -> WorkspaceSurfaceActivity
    let onFocusPane: (String) -> Void
    let onSelectPaneItem: (String, String) -> Void
    let onCreatePaneItem: (String) -> Void
    let onCreateBrowserItem: (String) -> Void
    let onClosePaneItem: (String, String) -> Void
    let onClosePane: (String) -> Void
    let onSplitPane: (String, WorkspacePaneSplitDirection) -> Void
    let onFocusDirection: (String, WorkspacePaneFocusDirection) -> Void
    let onResizePane: (String, WorkspacePaneSplitDirection, UInt16) -> Void
    let onEqualize: (String) -> Void
    let onToggleZoom: (String) -> Void
    let onSurfaceExit: (String) -> Void
    let onUpdateTabTitle: (String) -> Void
    let onNewTab: () -> Bool
    let onCloseTabAction: (ghostty_action_close_tab_mode_e) -> Bool
    let onGotoTabAction: (ghostty_action_goto_tab_e) -> Bool
    let onMoveTabAction: (ghostty_action_move_tab_s) -> Bool
    let onMovePaneItem: (String, String, String, Int) -> Void
    let onSplitPaneItem: (String, String, String, WorkspacePaneSplitDirection) -> Void
    let onSetSplitRatio: (WorkspacePaneTree.Path, Double) -> Void
    let onMovePane: (String, String, WorkspacePaneSplitDirection) -> Void

    @State private var paneDragSession: WorkspacePaneDragSession?
    @State private var paneItemDragSession: WorkspacePaneItemDragSession?
    @State private var itemFramesByItemID: [String: CGRect] = [:]
    @State private var tabStripFramesByPaneID: [String: CGRect] = [:]

    var body: some View {
        Group {
            if let zoomedPaneID = tab.tree.zoomedPaneId,
               let zoomedPane = tab.tree.find(paneID: zoomedPaneID) {
                zoomedLayoutView(for: zoomedPane)
            } else if let root = tab.tree.root {
                flatLayoutView(for: root)
            } else {
                EmptyView()
            }
        }
    }

    private func zoomedLayoutView(for pane: WorkspacePaneState) -> some View {
        GeometryReader { geometry in
            let leafFrame = WorkspacePaneTree.LeafFrame(
                pane: pane,
                frame: CGRect(origin: .zero, size: geometry.size)
            )
            paneCanvasView(leafFrames: [leafFrame], splitHandles: [])
        }
    }

    private func flatLayoutView(for root: WorkspacePaneTree.Node) -> some View {
        GeometryReader { geometry in
            let canvasFrame = CGRect(origin: .zero, size: geometry.size)
            let leafFrames = root.leafFrames(in: canvasFrame)
            let splitHandles = root.splitHandles(in: canvasFrame, path: WorkspacePaneTree.Path(components: []))
            paneCanvasView(leafFrames: leafFrames, splitHandles: splitHandles)
        }
    }

    private func paneCanvasView(
        leafFrames: [WorkspacePaneTree.LeafFrame],
        splitHandles: [WorkspacePaneTree.SplitHandle]
    ) -> some View {
        let paneDropTarget = resolvedPaneDropTarget(in: leafFrames)
        let paneItemDropTarget = resolvedPaneItemDropTarget(in: leafFrames)

        return ZStack(alignment: .topLeading) {
            ForEach(leafFrames, id: \.pane.id) { leaf in
                paneView(
                    for: leaf.pane,
                    isZoomed: tab.tree.zoomedPaneId == leaf.pane.id,
                    isDraggingPane: paneDragSession?.paneID == leaf.pane.id,
                    dropDirection: resolvedPaneDropDirection(
                        paneID: leaf.pane.id,
                        paneDropTarget: paneDropTarget,
                        paneItemDropTarget: paneItemDropTarget
                    ),
                    draggedItemID: paneItemDragSession?.itemID,
                    itemDropTarget: resolvedItemChipDropTarget(
                        paneID: leaf.pane.id,
                        paneItemDropTarget: paneItemDropTarget
                    ),
                    showsItemMergeTarget: resolvedItemMergeTarget(
                        paneID: leaf.pane.id,
                        paneItemDropTarget: paneItemDropTarget
                    ),
                    onPaneDragChanged: { location in
                        paneItemDragSession = nil
                        paneDragSession = WorkspacePaneDragSession(paneID: leaf.pane.id, location: location)
                    },
                    onPaneDragEnded: { location in
                        handlePaneDragEnded(
                            sourcePaneID: leaf.pane.id,
                            location: location,
                            leafFrames: leafFrames
                        )
                    },
                    onPaneItemDragChanged: { itemID, location in
                        paneDragSession = nil
                        paneItemDragSession = WorkspacePaneItemDragSession(
                            sourcePaneID: leaf.pane.id,
                            itemID: itemID,
                            location: location
                        )
                    },
                    onPaneItemDragEnded: { itemID, location in
                        handlePaneItemDragEnded(
                            sourcePaneID: leaf.pane.id,
                            itemID: itemID,
                            location: location,
                            leafFrames: leafFrames
                        )
                    }
                )
                .frame(
                    width: max(0, leaf.frame.width),
                    height: max(0, leaf.frame.height)
                )
                .offset(x: leaf.frame.minX, y: leaf.frame.minY)
                .id(leaf.pane.id)
            }

            ForEach(splitHandles, id: \.path) { handle in
                SplitHandleOverlay(
                    handle: handle,
                    onRatioChange: { ratio in
                        onSetSplitRatio(handle.path, ratio)
                    },
                    onEqualize: {
                        onEqualize(tab.focusedPaneId)
                    }
                )
            }
        }
        .coordinateSpace(name: Self.canvasCoordinateSpaceName)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onPreferenceChange(WorkspacePaneItemFramePreferenceKey.self) { preferences in
            itemFramesByItemID = Dictionary(
                uniqueKeysWithValues: preferences.map { ($0.itemID, $0.frame) }
            )
        }
        .onPreferenceChange(WorkspacePaneTabStripFramePreferenceKey.self) { preferences in
            tabStripFramesByPaneID = Dictionary(
                uniqueKeysWithValues: preferences.map { ($0.paneID, $0.frame) }
            )
        }
    }

    private func paneView(
        for pane: WorkspacePaneState,
        isZoomed: Bool,
        isDraggingPane: Bool,
        dropDirection: WorkspacePaneSplitDirection?,
        draggedItemID: String?,
        itemDropTarget: WorkspacePaneItemChipDropTarget?,
        showsItemMergeTarget: Bool,
        onPaneDragChanged: @escaping (CGPoint) -> Void,
        onPaneDragEnded: @escaping (CGPoint) -> Void,
        onPaneItemDragChanged: @escaping (String, CGPoint) -> Void,
        onPaneItemDragEnded: @escaping (String, CGPoint) -> Void
    ) -> some View {
        let activeItem = pane.selectedItem
            ?? pane.items.last
            ?? WorkspacePaneItemState(
                request: pane.request,
                title: pane.selectedTitle
            )

        return WorkspaceTerminalPaneView(
            pane: pane,
            selectedItem: activeItem,
            terminalModel: activeItem.isTerminal ? surfaceModelForPaneItem(pane, activeItem) : nil,
            browserModel: activeItem.isBrowser ? browserModelForPaneItem(pane, activeItem) : nil,
            surfaceActivity: surfaceActivityForPaneItem(pane, activeItem),
            isFocused: isTabSelected && tab.focusedPaneId == pane.id,
            isZoomed: isZoomed,
            isDraggingPane: isDraggingPane,
            dropDirection: dropDirection,
            draggedItemID: draggedItemID,
            itemDropTarget: itemDropTarget,
            showsItemMergeTarget: showsItemMergeTarget,
            dragCoordinateSpaceName: Self.canvasCoordinateSpaceName,
            onFocusPane: onFocusPane,
            onSelectItem: onSelectPaneItem,
            onCreateItem: onCreatePaneItem,
            onCreateBrowserItem: onCreateBrowserItem,
            onCloseItem: onClosePaneItem,
            onClosePane: onClosePane,
            onSplitPane: onSplitPane,
            onFocusDirection: onFocusDirection,
            onResizePane: onResizePane,
            onEqualize: onEqualize,
            onToggleZoom: onToggleZoom,
            onSurfaceExit: onSurfaceExit,
            onUpdateTabTitle: onUpdateTabTitle,
            onNewTab: onNewTab,
            onCloseTabAction: onCloseTabAction,
            onGotoTabAction: onGotoTabAction,
            onMoveTabAction: onMoveTabAction,
            onPaneDragChanged: onPaneDragChanged,
            onPaneDragEnded: onPaneDragEnded,
            onPaneItemDragChanged: onPaneItemDragChanged,
            onPaneItemDragEnded: onPaneItemDragEnded
        )
    }

    private func handlePaneDragEnded(
        sourcePaneID: String,
        location: CGPoint,
        leafFrames: [WorkspacePaneTree.LeafFrame]
    ) {
        defer {
            paneDragSession = nil
        }
        guard let target = resolvedPaneDropTarget(
            sourcePaneID: sourcePaneID,
            location: location,
            leafFrames: leafFrames
        ) else {
            return
        }
        onMovePane(sourcePaneID, target.paneID, target.direction)
    }

    private func handlePaneItemDragEnded(
        sourcePaneID: String,
        itemID: String,
        location: CGPoint,
        leafFrames: [WorkspacePaneTree.LeafFrame]
    ) {
        defer {
            paneItemDragSession = nil
        }
        guard let target = resolvedPaneItemDropTarget(
            sourcePaneID: sourcePaneID,
            itemID: itemID,
            location: location,
            leafFrames: leafFrames
        ) else {
            return
        }

        switch target {
        case let .strip(targetPaneID, _, targetIndex):
            onMovePaneItem(sourcePaneID, itemID, targetPaneID, targetIndex)
        case let .merge(targetPaneID):
            let targetIndex = tab.tree.find(paneID: targetPaneID)?.items.count ?? 0
            onMovePaneItem(sourcePaneID, itemID, targetPaneID, targetIndex)
        case let .split(targetPaneID, direction):
            onSplitPaneItem(sourcePaneID, itemID, targetPaneID, direction)
        }
    }

    private func resolvedPaneDropTarget(
        in leafFrames: [WorkspacePaneTree.LeafFrame]
    ) -> WorkspacePaneDropTarget? {
        guard let paneDragSession else {
            return nil
        }
        return resolvedPaneDropTarget(
            sourcePaneID: paneDragSession.paneID,
            location: paneDragSession.location,
            leafFrames: leafFrames
        )
    }

    private func resolvedPaneDropTarget(
        sourcePaneID: String,
        location: CGPoint,
        leafFrames: [WorkspacePaneTree.LeafFrame]
    ) -> WorkspacePaneDropTarget? {
        for leaf in leafFrames where leaf.pane.id != sourcePaneID && leaf.frame.contains(location) {
            guard let direction = resolvedDropDirection(location: location, in: leaf.frame) else {
                return nil
            }
            return WorkspacePaneDropTarget(paneID: leaf.pane.id, direction: direction)
        }
        return nil
    }

    private func resolvedPaneItemDropTarget(
        in leafFrames: [WorkspacePaneTree.LeafFrame]
    ) -> WorkspacePaneItemDropTarget? {
        guard let paneItemDragSession else {
            return nil
        }
        return resolvedPaneItemDropTarget(
            sourcePaneID: paneItemDragSession.sourcePaneID,
            itemID: paneItemDragSession.itemID,
            location: paneItemDragSession.location,
            leafFrames: leafFrames
        )
    }

    private func resolvedPaneItemDropTarget(
        sourcePaneID: String,
        itemID: String,
        location: CGPoint,
        leafFrames: [WorkspacePaneTree.LeafFrame]
    ) -> WorkspacePaneItemDropTarget? {
        for leaf in leafFrames where leaf.frame.contains(location) {
            if leaf.pane.id == sourcePaneID {
                if let stripTarget = resolvedStripDropTarget(
                    for: leaf.pane,
                    sourcePaneID: sourcePaneID,
                    sourceItemID: itemID,
                    location: location
                ) {
                    return .strip(
                        targetPaneID: leaf.pane.id,
                        target: stripTarget.target,
                        targetIndex: stripTarget.targetIndex
                    )
                }
                guard leaf.pane.items.count > 1,
                      let direction = resolvedDropDirection(location: location, in: leaf.frame) else {
                    return nil
                }
                return .split(targetPaneID: leaf.pane.id, direction: direction)
            }

            if let stripTarget = resolvedStripDropTarget(
                for: leaf.pane,
                sourcePaneID: sourcePaneID,
                sourceItemID: itemID,
                location: location
            ) {
                return .strip(
                    targetPaneID: leaf.pane.id,
                    target: stripTarget.target,
                    targetIndex: stripTarget.targetIndex
                )
            }
            if let direction = resolvedDropDirection(location: location, in: leaf.frame) {
                return .split(targetPaneID: leaf.pane.id, direction: direction)
            }
            return .merge(targetPaneID: leaf.pane.id)
        }
        return nil
    }

    private func resolvedStripDropTarget(
        for pane: WorkspacePaneState,
        sourcePaneID: String,
        sourceItemID: String,
        location: CGPoint
    ) -> WorkspacePaneItemStripDropTarget? {
        guard let stripFrame = tabStripFramesByPaneID[pane.id], stripFrame.contains(location) else {
            return nil
        }

        let orderedFrames = pane.items.compactMap { item -> (itemID: String, frame: CGRect)? in
            if pane.id == sourcePaneID, item.id == sourceItemID {
                return nil
            }
            guard let frame = itemFramesByItemID[item.id] else {
                return nil
            }
            return (item.id, frame)
        }
        guard let last = orderedFrames.last else {
            return nil
        }

        for (index, candidate) in orderedFrames.enumerated() {
            if location.x < candidate.frame.midX {
                return WorkspacePaneItemStripDropTarget(
                    target: WorkspacePaneItemChipDropTarget(itemID: candidate.itemID, edge: .leading),
                    targetIndex: index
                )
            }
        }

        return WorkspacePaneItemStripDropTarget(
            target: WorkspacePaneItemChipDropTarget(itemID: last.itemID, edge: .trailing),
            targetIndex: orderedFrames.count
        )
    }

    private func resolvedPaneDropDirection(
        paneID: String,
        paneDropTarget: WorkspacePaneDropTarget?,
        paneItemDropTarget: WorkspacePaneItemDropTarget?
    ) -> WorkspacePaneSplitDirection? {
        if paneDragSession != nil {
            guard paneDropTarget?.paneID == paneID else {
                return nil
            }
            return paneDropTarget?.direction
        }
        guard let paneItemDropTarget else {
            return nil
        }
        if case let .split(targetPaneID, direction) = paneItemDropTarget,
           targetPaneID == paneID {
            return direction
        }
        return nil
    }

    private func resolvedItemChipDropTarget(
        paneID: String,
        paneItemDropTarget: WorkspacePaneItemDropTarget?
    ) -> WorkspacePaneItemChipDropTarget? {
        guard let paneItemDropTarget,
              case let .strip(targetPaneID, target, _) = paneItemDropTarget,
              targetPaneID == paneID else {
            return nil
        }
        return target
    }

    private func resolvedItemMergeTarget(
        paneID: String,
        paneItemDropTarget: WorkspacePaneItemDropTarget?
    ) -> Bool {
        guard let paneItemDropTarget,
              case let .merge(targetPaneID) = paneItemDropTarget else {
            return false
        }
        return targetPaneID == paneID
    }

    private func resolvedDropDirection(
        location: CGPoint,
        in frame: CGRect
    ) -> WorkspacePaneSplitDirection? {
        let horizontalEdgeWidth = min(max(frame.width * 0.22, 44), 88)
        let verticalEdgeHeight = min(max(frame.height * 0.22, 36), 72)

        let leftRect = CGRect(x: frame.minX, y: frame.minY, width: horizontalEdgeWidth, height: frame.height)
        let rightRect = CGRect(x: frame.maxX - horizontalEdgeWidth, y: frame.minY, width: horizontalEdgeWidth, height: frame.height)
        let topRect = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: verticalEdgeHeight)
        let bottomRect = CGRect(x: frame.minX, y: frame.maxY - verticalEdgeHeight, width: frame.width, height: verticalEdgeHeight)

        var candidates: [(WorkspacePaneSplitDirection, CGFloat)] = []
        if leftRect.contains(location) {
            candidates.append((.left, location.x - frame.minX))
        }
        if rightRect.contains(location) {
            candidates.append((.right, frame.maxX - location.x))
        }
        if topRect.contains(location) {
            candidates.append((.top, location.y - frame.minY))
        }
        if bottomRect.contains(location) {
            candidates.append((.down, frame.maxY - location.y))
        }
        return candidates.min(by: { $0.1 < $1.1 })?.0
    }
}

private struct WorkspacePaneDragSession {
    let paneID: String
    let location: CGPoint
}

private struct WorkspacePaneItemDragSession {
    let sourcePaneID: String
    let itemID: String
    let location: CGPoint
}

private struct WorkspacePaneDropTarget: Equatable {
    let paneID: String
    let direction: WorkspacePaneSplitDirection
}

private struct WorkspacePaneItemStripDropTarget {
    let target: WorkspacePaneItemChipDropTarget
    let targetIndex: Int
}

private enum WorkspacePaneItemDropTarget: Equatable {
    case strip(targetPaneID: String, target: WorkspacePaneItemChipDropTarget, targetIndex: Int)
    case merge(targetPaneID: String)
    case split(targetPaneID: String, direction: WorkspacePaneSplitDirection)
}

private struct SplitHandleOverlay: View {
    let handle: WorkspacePaneTree.SplitHandle
    let onRatioChange: (Double) -> Void
    let onEqualize: () -> Void

    @State private var isHovered = false

    private let minSize: CGFloat = 10

    var body: some View {
        ZStack {
            Rectangle()
                .fill(NativeTheme.border.opacity(isHovered ? 0.95 : 0.45))
                .frame(
                    width: handle.visibleFrame.width > 0 ? handle.visibleFrame.width : nil,
                    height: handle.visibleFrame.height > 0 ? handle.visibleFrame.height : nil
                )
        }
        .frame(width: handle.hitFrame.width, height: handle.hitFrame.height)
        .contentShape(.rect)
        .offset(x: handle.hitFrame.minX, y: handle.hitFrame.minY)
        .gesture(
            DragGesture(coordinateSpace: .named(WorkspaceSplitTreeView.canvasCoordinateSpaceName))
                .onChanged { gesture in
                    onRatioChange(resolvedRatio(for: gesture.location))
                }
        )
        .onTapGesture(count: 2) {
            onEqualize()
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityLabel("调整分屏比例")
    }

    private func resolvedRatio(for location: CGPoint) -> Double {
        switch handle.direction {
        case .horizontal:
            guard handle.splitBounds.width > 0 else { return 0.5 }
            let minX = handle.splitBounds.minX
            let ratio = (location.x - minX) / handle.splitBounds.width
            return min(max(Double(ratio), 0.1), 0.9)
        case .vertical:
            guard handle.splitBounds.height > 0 else { return 0.5 }
            let minY = handle.splitBounds.minY
            let ratio = (location.y - minY) / handle.splitBounds.height
            return min(max(Double(ratio), 0.1), 0.9)
        }
    }
}
