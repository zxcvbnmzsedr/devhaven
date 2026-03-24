import SwiftUI
import GhosttyKit
import DevHavenCore

struct WorkspaceSplitTreeView: View {
    fileprivate static let canvasCoordinateSpaceName = "workspace-split-tree-canvas"

    let tab: WorkspaceTabState
    let isTabSelected: Bool
    let surfaceModelForPane: (WorkspacePaneState) -> GhosttySurfaceHostModel
    let onFocusPane: (String) -> Void
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
    let onSetSplitRatio: (WorkspacePaneTree.Path, Double) -> Void

    var body: some View {
        Group {
            if let zoomedPaneID = tab.tree.zoomedPaneId,
               let zoomedPane = tab.tree.find(paneID: zoomedPaneID) {
                paneView(for: zoomedPane, isZoomed: true)
                    .id(zoomedPane.id)
            } else if let root = tab.tree.root {
                flatLayoutView(for: root)
            } else {
                EmptyView()
            }
        }
    }

    private func flatLayoutView(for root: WorkspacePaneTree.Node) -> some View {
        GeometryReader { geometry in
            let canvasFrame = CGRect(origin: .zero, size: geometry.size)
            let leafFrames = root.leafFrames(in: canvasFrame)
            let splitHandles = root.splitHandles(in: canvasFrame, path: WorkspacePaneTree.Path(components: []))

            ZStack(alignment: .topLeading) {
                ForEach(leafFrames, id: \.pane.id) { leaf in
                    paneView(for: leaf.pane, isZoomed: false)
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
        }
    }

    private func paneView(for pane: WorkspacePaneState, isZoomed: Bool) -> some View {
        WorkspaceTerminalPaneView(
            pane: pane,
            model: surfaceModelForPane(pane),
            isFocused: isTabSelected && tab.focusedPaneId == pane.id,
            isZoomed: isZoomed,
            onFocusPane: onFocusPane,
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
            onMoveTabAction: onMoveTabAction
        )
    }
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
                .fill(NativeTheme.border.opacity(0.9))
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
                .onEnded { gesture in
                    onRatioChange(resolvedRatio(for: gesture.location))
                }
        )
        .onTapGesture(count: 2, perform: onEqualize)
        .onHover { hovering in
            guard hovering != isHovered else {
                return
            }
            isHovered = hovering
            if hovering {
                hoverCursor.push()
            } else {
                NSCursor.pop()
            }
        }
        .onDisappear {
            if isHovered {
                isHovered = false
                NSCursor.pop()
            }
        }
    }

    private var hoverCursor: NSCursor {
        switch handle.direction {
        case .horizontal:
            return .resizeLeftRight
        case .vertical:
            return .resizeUpDown
        }
    }

    private func resolvedRatio(for location: CGPoint) -> Double {
        switch handle.direction {
        case .horizontal:
            guard handle.splitBounds.width > 0 else {
                return 0.5
            }
            let minX = handle.splitBounds.minX + minSize
            let maxX = handle.splitBounds.maxX - minSize
            let resolvedX = min(max(minX, location.x), maxX)
            return Double((resolvedX - handle.splitBounds.minX) / handle.splitBounds.width)
        case .vertical:
            guard handle.splitBounds.height > 0 else {
                return 0.5
            }
            let minY = handle.splitBounds.minY + minSize
            let maxY = handle.splitBounds.maxY - minSize
            let resolvedY = min(max(minY, location.y), maxY)
            return Double((resolvedY - handle.splitBounds.minY) / handle.splitBounds.height)
        }
    }
}
