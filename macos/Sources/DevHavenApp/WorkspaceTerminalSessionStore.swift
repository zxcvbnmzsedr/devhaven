import Foundation
import GhosttyKit
import DevHavenCore

@MainActor
final class WorkspaceTerminalSessionStore: ObservableObject {
    private var modelsByPaneID: [String: GhosttySurfaceHostModel] = [:]

    var modelCount: Int {
        modelsByPaneID.count
    }

    func model(
        for pane: WorkspacePaneState,
        onFocusChange: ((Bool) -> Void)? = nil,
        onSurfaceExit: (() -> Void)? = nil,
        onTabTitleChange: ((String) -> Void)? = nil,
        onNotificationEvent: ((String, String) -> Void)? = nil,
        onTaskStatusChange: ((WorkspaceTaskStatus) -> Void)? = nil,
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
            onNotificationEvent: onNotificationEvent,
            onTaskStatusChange: onTaskStatusChange,
            onNewTab: onNewTab,
            onCloseTab: onCloseTab,
            onGotoTab: onGotoTab,
            onMoveTab: onMoveTab,
            onSplitAction: onSplitAction
        )
        modelsByPaneID[pane.id] = model
        return model
    }

    @discardableResult
    func warmSelectedPane(in controller: GhosttyWorkspaceController) -> GhosttySurfaceHostModel? {
        guard let selectedPane = controller.selectedPane else {
            return nil
        }
        return model(for: selectedPane)
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

@MainActor
final class WorkspaceTerminalStoreRegistry: ObservableObject {
    private var storesByProjectPath: [String: WorkspaceTerminalSessionStore] = [:]

    var storeCount: Int {
        storesByProjectPath.count
    }

    func store(for projectPath: String) -> WorkspaceTerminalSessionStore {
        if let existing = storesByProjectPath[projectPath] {
            return existing
        }
        let store = WorkspaceTerminalSessionStore()
        storesByProjectPath[projectPath] = store
        return store
    }

    func syncRetainedProjectPaths(_ projectPaths: Set<String>) {
        let removedPaths = Set(storesByProjectPath.keys).subtracting(projectPaths)
        for projectPath in removedPaths {
            storesByProjectPath[projectPath]?.releaseAll()
            storesByProjectPath.removeValue(forKey: projectPath)
        }
    }

    @discardableResult
    func warmActiveWorkspaceSession(
        sessions: [OpenWorkspaceSessionState],
        activeProjectPath: String?
    ) -> GhosttySurfaceHostModel? {
        guard let activeProjectPath,
              let session = sessions.first(where: { $0.projectPath == activeProjectPath })
        else {
            return nil
        }
        return store(for: activeProjectPath).warmSelectedPane(in: session.controller)
    }
}
