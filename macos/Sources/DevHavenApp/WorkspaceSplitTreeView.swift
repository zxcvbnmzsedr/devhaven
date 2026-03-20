import SwiftUI
import GhosttyKit
import DevHavenCore

struct WorkspaceSplitTreeView: View {
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
                WorkspaceTerminalPaneView(
                    pane: zoomedPane,
                    model: surfaceModelForPane(zoomedPane),
                    isFocused: isTabSelected && tab.focusedPaneId == zoomedPane.id,
                    isZoomed: true,
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
            } else if let root = tab.tree.root {
                renderNode(root, path: WorkspacePaneTree.Path(components: []))
            } else {
                EmptyView()
            }
        }
    }

    private func renderNode(_ node: WorkspacePaneTree.Node, path: WorkspacePaneTree.Path) -> AnyView {
        switch node {
        case let .leaf(pane):
            return AnyView(WorkspaceTerminalPaneView(
                pane: pane,
                model: surfaceModelForPane(pane),
                isFocused: isTabSelected && tab.focusedPaneId == pane.id,
                isZoomed: false,
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
            ))

        case let .split(split):
            return AnyView(WorkspaceSplitView(
                direction: split.direction,
                ratio: split.ratio,
                onRatioChange: { ratio in
                    onSetSplitRatio(path, ratio)
                }
            ) {
                renderNode(split.left, path: WorkspacePaneTree.Path(components: path.components + [.left]))
            } trailing: {
                renderNode(split.right, path: WorkspacePaneTree.Path(components: path.components + [.right]))
            })
        }
    }
}
