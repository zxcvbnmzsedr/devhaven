import Foundation
import GhosttyKit
import DevHavenCore

@MainActor
final class WorkspaceSurfaceRegistry: ObservableObject {
    private var modelsByPaneID: [String: GhosttySurfaceHostModel] = [:]

    var modelCount: Int {
        modelsByPaneID.count
    }

    func model(
        for pane: WorkspacePaneState,
        onFocusChange: ((Bool) -> Void)? = nil,
        onSurfaceExit: (() -> Void)? = nil,
        onTabTitleChange: ((String) -> Void)? = nil,
        onNewTab: (() -> Bool)? = nil,
        onCloseTab: ((ghostty_action_close_tab_mode_e) -> Bool)? = nil,
        onGotoTab: ((ghostty_action_goto_tab_e) -> Bool)? = nil,
        onMoveTab: ((ghostty_action_move_tab_s) -> Bool)? = nil,
        onSplitAction: ((GhosttySplitAction) -> Bool)? = nil
    ) -> GhosttySurfaceHostModel {
        if let existing = modelsByPaneID[pane.id] {
            return existing
        }

        let model = GhosttySurfaceHostModel(
            request: pane.request,
            onFocusChange: onFocusChange,
            onSurfaceExit: onSurfaceExit,
            onTabTitleChange: onTabTitleChange,
            onNewTab: onNewTab,
            onCloseTab: onCloseTab,
            onGotoTab: onGotoTab,
            onMoveTab: onMoveTab,
            onSplitAction: onSplitAction
        )
        modelsByPaneID[pane.id] = model
        return model
    }

    func syncRetainedPaneIDs(_ paneIDs: Set<String>) {
        let removedIDs = Set(modelsByPaneID.keys).subtracting(paneIDs)
        for paneID in removedIDs {
            modelsByPaneID[paneID]?.releaseSurface()
            modelsByPaneID.removeValue(forKey: paneID)
        }
    }

    func releaseAll() {
        for model in modelsByPaneID.values {
            model.releaseSurface()
        }
        modelsByPaneID.removeAll()
    }
}
