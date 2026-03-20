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
                paneView(for: zoomedPane, isZoomed: true)
                    .id(zoomedPane.id)
            } else if let root = tab.tree.root {
                rootView(for: root)
            } else {
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func rootView(for root: WorkspacePaneTree.Node) -> some View {
        let subtree = SubtreeView(
            node: root,
            path: WorkspacePaneTree.Path(components: []),
            tab: tab,
            isTabSelected: isTabSelected,
            surfaceModelForPane: surfaceModelForPane,
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
            onMoveTabAction: onMoveTabAction,
            onSetSplitRatio: onSetSplitRatio
        )

        if WorkspaceSplitTreeViewKeyPolicy.shouldKeyRootByStructuralIdentity {
            subtree.id(root.structuralIdentity)
        } else {
            subtree
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

    private struct SubtreeView: View {
        let node: WorkspacePaneTree.Node
        let path: WorkspacePaneTree.Path
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
            switch node {
            case let .leaf(pane):
                WorkspaceTerminalPaneView(
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
                )
                .id(pane.id)

            case let .split(split):
                splitSubtreeView(for: split)
            }
        }

        @ViewBuilder
        private func splitSubtreeView(for split: WorkspaceSplitState) -> some View {
            let splitView = WorkspaceSplitView(
                direction: split.direction,
                ratio: split.ratio,
                onRatioChange: { ratio in
                    onSetSplitRatio(path, ratio)
                },
                onEqualize: {
                    onEqualize(tab.focusedPaneId)
                }
            ) {
                SubtreeView(
                    node: split.left,
                    path: WorkspacePaneTree.Path(components: path.components + [.left]),
                    tab: tab,
                    isTabSelected: isTabSelected,
                    surfaceModelForPane: surfaceModelForPane,
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
                    onMoveTabAction: onMoveTabAction,
                    onSetSplitRatio: onSetSplitRatio
                )
            } trailing: {
                SubtreeView(
                    node: split.right,
                    path: WorkspacePaneTree.Path(components: path.components + [.right]),
                    tab: tab,
                    isTabSelected: isTabSelected,
                    surfaceModelForPane: surfaceModelForPane,
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
                    onMoveTabAction: onMoveTabAction,
                    onSetSplitRatio: onSetSplitRatio
                )
            }

            if WorkspaceSplitTreeViewKeyPolicy.shouldKeySplitSubtreeByStructuralIdentity {
                splitView.id(node.structuralIdentity)
            } else {
                splitView
            }
        }
    }
}
