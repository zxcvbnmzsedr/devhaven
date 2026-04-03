import Foundation
import GhosttyKit
import DevHavenCore

@MainActor
final class WorkspaceTerminalSessionStore: ObservableObject {
    private var modelsByItemID: [String: GhosttySurfaceHostModel] = [:]
    private var paneIDByItemID: [String: String] = [:]
    private var selectedItemIDByPaneID: [String: String] = [:]
    private var trackedCodexPaneIDs: Set<String> = []

    var onModelCreated: ((String, GhosttySurfaceHostModel) -> Void)?

    var modelCount: Int {
        modelsByItemID.count
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
        let item = pane.selectedItem ?? pane.items.last ?? WorkspacePaneItemState(
            request: pane.request,
            title: pane.selectedTitle
        )
        return model(
            for: item,
            in: pane,
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
    }

    func model(
        for item: WorkspacePaneItemState,
        in pane: WorkspacePaneState,
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
        paneIDByItemID[item.id] = pane.id
        selectedItemIDByPaneID[pane.id] = pane.selectedItem?.id

        if let existing = modelsByItemID[item.id] {
            syncCodexTrackingForLoadedModels()
            return existing
        }

        let model = GhosttySurfaceHostModel(
            request: item.request,
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
        modelsByItemID[item.id] = model
        model.setCodexDisplayTrackingEnabled(
            trackedCodexPaneIDs.contains(pane.id) && pane.selectedItem?.id == item.id
        )
        onModelCreated?(pane.id, model)
        return model
    }

    @discardableResult
    func warmSelectedPane(in controller: GhosttyWorkspaceController) -> GhosttySurfaceHostModel? {
        guard let selectedPane = controller.selectedPane,
              let selectedItem = selectedPane.selectedItem
        else {
            return nil
        }
        return model(for: selectedItem, in: selectedPane)
    }

    func modelIfLoaded(for paneID: String) -> GhosttySurfaceHostModel? {
        guard let selectedItemID = selectedItemIDByPaneID[paneID] else {
            return nil
        }
        return modelsByItemID[selectedItemID]
    }

    func syncSelectedItemIDs(_ selectedItemIDsByPaneID: [String: String]) {
        self.selectedItemIDByPaneID = selectedItemIDsByPaneID
        syncCodexTrackingForLoadedModels()
    }

    func syncCodexDisplayTracking(_ trackedPaneIDs: Set<String>) {
        trackedCodexPaneIDs = trackedPaneIDs
        syncCodexTrackingForLoadedModels()
    }

    func syncRetainedItemIDs(_ itemIDs: Set<String>) {
        let removedIDs = Set(modelsByItemID.keys).subtracting(itemIDs)
        for itemID in removedIDs {
            modelsByItemID[itemID]?.releaseSurface()
            modelsByItemID.removeValue(forKey: itemID)
            paneIDByItemID.removeValue(forKey: itemID)
        }
        let retainedPaneIDs = Set(paneIDByItemID.values)
        selectedItemIDByPaneID = selectedItemIDByPaneID.filter { retainedPaneIDs.contains($0.key) }
    }

    func releaseAll() {
        for model in modelsByItemID.values {
            model.releaseSurface()
        }
        modelsByItemID.removeAll()
        paneIDByItemID.removeAll()
        selectedItemIDByPaneID.removeAll()
    }

    private func syncCodexTrackingForLoadedModels() {
        for (itemID, model) in modelsByItemID {
            guard let paneID = paneIDByItemID[itemID] else {
                model.setCodexDisplayTrackingEnabled(false)
                continue
            }
            model.setCodexDisplayTrackingEnabled(
                trackedCodexPaneIDs.contains(paneID) && selectedItemIDByPaneID[paneID] == itemID
            )
        }
    }
}

@MainActor
final class WorkspaceTerminalStoreRegistry: ObservableObject {
    private var storesByProjectPath: [String: WorkspaceTerminalSessionStore] = [:]
    private var codexDisplayModelCreatedObserver: ((String, String, GhosttySurfaceHostModel) -> Void)?

    var storeCount: Int {
        storesByProjectPath.count
    }

    func store(for projectPath: String) -> WorkspaceTerminalSessionStore {
        if let existing = storesByProjectPath[projectPath] {
            return existing
        }
        let store = WorkspaceTerminalSessionStore()
        wireCodexDisplayObserver(for: store, projectPath: projectPath)
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

    func modelIfLoaded(for projectPath: String, paneID: String) -> GhosttySurfaceHostModel? {
        storesByProjectPath[projectPath]?.modelIfLoaded(for: paneID)
    }

    func syncSelectedItemIDs(
        _ selectedItemIDsByPaneIDByProjectPath: [String: [String: String]]
    ) {
        for (projectPath, store) in storesByProjectPath {
            store.syncSelectedItemIDs(selectedItemIDsByPaneIDByProjectPath[projectPath] ?? [:])
        }
    }

    func syncCodexDisplayTracking(
        _ trackedPaneIDsByProjectPath: [String: Set<String>]
    ) {
        for (projectPath, store) in storesByProjectPath {
            store.syncCodexDisplayTracking(trackedPaneIDsByProjectPath[projectPath] ?? [])
        }
    }

    func setCodexDisplayModelCreatedObserver(
        _ observer: ((String, String, GhosttySurfaceHostModel) -> Void)?
    ) {
        codexDisplayModelCreatedObserver = observer
        for (projectPath, store) in storesByProjectPath {
            wireCodexDisplayObserver(for: store, projectPath: projectPath)
        }
    }

    private func wireCodexDisplayObserver(
        for store: WorkspaceTerminalSessionStore,
        projectPath: String
    ) {
        store.onModelCreated = { [weak self] paneID, model in
            self?.codexDisplayModelCreatedObserver?(projectPath, paneID, model)
        }
    }
}
