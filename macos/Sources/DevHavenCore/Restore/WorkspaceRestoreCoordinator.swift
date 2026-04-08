import Foundation

public enum WorkspacePaneSnapshotFreshness: Sendable {
    case autosave
    case flush
}

public typealias WorkspacePaneSnapshotProvider = @MainActor (
    _ projectPath: String,
    _ paneID: String,
    _ freshness: WorkspacePaneSnapshotFreshness
) -> WorkspaceTerminalRestoreContext?
public typealias WorkspaceEditorRestoreProvider = @MainActor (_ projectPath: String) -> WorkspaceEditorRestoreState

public struct WorkspaceEditorRestoreState: Equatable, Sendable {
    public var tabs: [WorkspaceEditorTabRestoreSnapshot]
    public var selectedPresentedTab: WorkspaceRestorePresentedTabSelection?
    public var presentation: WorkspaceEditorPresentationState?

    public init(
        tabs: [WorkspaceEditorTabRestoreSnapshot] = [],
        selectedPresentedTab: WorkspaceRestorePresentedTabSelection? = nil,
        presentation: WorkspaceEditorPresentationState? = nil
    ) {
        self.tabs = tabs
        self.selectedPresentedTab = selectedPresentedTab
        self.presentation = presentation
    }
}

@MainActor
final class WorkspaceRestoreCoordinator {
    private let store: WorkspaceRestoreStore
    private let autosaveDelayNanoseconds: UInt64
    private var pendingAutosaveTask: Task<Void, Never>?
    private var lastSnapshot: WorkspaceRestoreSnapshot?
    private var autosaveGeneration: UInt64 = 0

    init(
        store: WorkspaceRestoreStore = WorkspaceRestoreStore(),
        autosaveDelayNanoseconds: UInt64 = 400_000_000
    ) {
        self.store = store
        self.autosaveDelayNanoseconds = autosaveDelayNanoseconds
    }

    deinit {
        pendingAutosaveTask?.cancel()
    }

    func loadSnapshot() -> WorkspaceRestoreSnapshot? {
        let hydrated = store.loadSnapshot().map(hydrateSnapshot(_:))
        lastSnapshot = hydrated
        return hydrated
    }

    func scheduleAutosave(
        activeProjectPath: String?,
        selectedProjectPath: String?,
        sessions: [OpenWorkspaceSessionState],
        paneSnapshotProvider: WorkspacePaneSnapshotProvider?,
        editorRestoreProvider: WorkspaceEditorRestoreProvider?
    ) {
        pendingAutosaveTask?.cancel()
        autosaveGeneration &+= 1
        let generation = autosaveGeneration
        pendingAutosaveTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            if self.autosaveDelayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: self.autosaveDelayNanoseconds)
            }
            guard !Task.isCancelled else {
                return
            }
            let snapshot = self.captureSnapshot(
                activeProjectPath: activeProjectPath,
                selectedProjectPath: selectedProjectPath,
                sessions: sessions,
                paneSnapshotProvider: paneSnapshotProvider,
                editorRestoreProvider: editorRestoreProvider,
                snapshotFreshness: .autosave
            )
            guard self.shouldPersistSnapshot(snapshot) else {
                return
            }
            do {
                let persistedSnapshot = try await self.persistAutosaveSnapshot(snapshot, generation: generation)
                guard !Task.isCancelled,
                      self.autosaveGeneration == generation
                else {
                    return
                }
                if let persistedSnapshot {
                    self.lastSnapshot = persistedSnapshot
                }
            } catch {
                return
            }
        }
    }

    func flushNow(
        activeProjectPath: String?,
        selectedProjectPath: String?,
        sessions: [OpenWorkspaceSessionState],
        paneSnapshotProvider: WorkspacePaneSnapshotProvider?,
        editorRestoreProvider: WorkspaceEditorRestoreProvider?
    ) throws {
        pendingAutosaveTask?.cancel()
        pendingAutosaveTask = nil

        let snapshot = captureSnapshot(
            activeProjectPath: activeProjectPath,
            selectedProjectPath: selectedProjectPath,
            sessions: sessions,
            paneSnapshotProvider: paneSnapshotProvider,
            editorRestoreProvider: editorRestoreProvider,
            snapshotFreshness: .flush
        )

        guard !snapshot.isEmpty else {
            guard lastSnapshot != nil else {
                return
            }
            try store.removeSnapshot()
            lastSnapshot = nil
            return
        }
        guard shouldPersistSnapshot(snapshot) else {
            return
        }

        let persistedSnapshot = try store.saveSnapshot(snapshot)
        lastSnapshot = persistedSnapshot
    }

    private func persistAutosaveSnapshot(
        _ snapshot: WorkspaceRestoreSnapshot,
        generation: UInt64
    ) async throws -> WorkspaceRestoreSnapshot? {
        let store = self.store
        return try await Task.detached(priority: .utility) {
            if snapshot.isEmpty {
                try store.removeSnapshot()
                return nil
            }
            return try store.saveAutosaveSnapshot(snapshot, generation: generation)
        }.value
    }

    private func shouldPersistSnapshot(_ snapshot: WorkspaceRestoreSnapshot) -> Bool {
        if snapshot.isEmpty {
            return lastSnapshot != nil
        }
        guard let lastSnapshot else {
            return true
        }
        return comparableSnapshot(snapshot) != comparableSnapshot(lastSnapshot)
    }

    private func comparableSnapshot(_ snapshot: WorkspaceRestoreSnapshot) -> WorkspaceRestoreSnapshot {
        var snapshot = snapshot
        snapshot.savedAt = .distantPast
        return snapshot
    }

    private func captureSnapshot(
        activeProjectPath: String?,
        selectedProjectPath: String?,
        sessions: [OpenWorkspaceSessionState],
        paneSnapshotProvider: WorkspacePaneSnapshotProvider?,
        editorRestoreProvider: WorkspaceEditorRestoreProvider?,
        snapshotFreshness: WorkspacePaneSnapshotFreshness
    ) -> WorkspaceRestoreSnapshot {
        let previousPaneMap = makePreviousPaneMap()
        let sessionSnapshots = sessions.map { session in
            var snapshot = session.controller.makeRestoreSnapshot(
                rootProjectPath: session.rootProjectPath,
                isQuickTerminal: session.isQuickTerminal,
                workspaceRootContext: session.workspaceRootContext,
                workspaceAlignmentGroupID: session.workspaceAlignmentGroupID
            )
            snapshot.tabs = snapshot.tabs.map { tab in
                var tab = tab
                tab.tree = WorkspacePaneTreeRestoreSnapshot(
                    root: enrich(
                        node: tab.tree.root,
                        projectPath: session.projectPath,
                        paneSnapshotProvider: paneSnapshotProvider,
                        previousPaneMap: previousPaneMap,
                        snapshotFreshness: snapshotFreshness
                    ),
                    zoomedPaneId: tab.tree.zoomedPaneId
                )
                return tab
            }
            let editorRestoreState = editorRestoreProvider?(session.projectPath) ?? WorkspaceEditorRestoreState()
            snapshot.editorTabs = editorRestoreState.tabs
            snapshot.selectedPresentedTab = editorRestoreState.selectedPresentedTab
            snapshot.editorPresentation = editorRestoreState.presentation
            return snapshot
        }

        return WorkspaceRestoreSnapshot(
            activeProjectPath: activeProjectPath,
            selectedProjectPath: selectedProjectPath,
            sessions: sessionSnapshots
        )
    }

    private func hydrateSnapshot(_ snapshot: WorkspaceRestoreSnapshot) -> WorkspaceRestoreSnapshot {
        var snapshot = snapshot
        snapshot.sessions = snapshot.sessions.map { session in
            var session = session
            session.tabs = session.tabs.map { tab in
                var tab = tab
                tab.tree = WorkspacePaneTreeRestoreSnapshot(
                    root: hydrate(node: tab.tree.root),
                    zoomedPaneId: tab.tree.zoomedPaneId
                )
                return tab
            }
            return session
        }
        return snapshot
    }

    private func hydrate(node: WorkspacePaneTreeRestoreSnapshot.Node) -> WorkspacePaneTreeRestoreSnapshot.Node {
        switch node {
        case let .leaf(pane):
            var pane = pane
            pane.items = pane.items.map { item in
                var item = item
                item.snapshotText = store.loadPaneText(for: item.snapshotTextRef)
                return item
            }
            return .leaf(pane)
        case let .split(split):
            return .split(
                WorkspaceSplitRestoreSnapshot(
                    direction: split.direction,
                    ratio: split.ratio,
                    left: hydrate(node: split.left),
                    right: hydrate(node: split.right)
                )
            )
        }
    }

    private func enrich(
        node: WorkspacePaneTreeRestoreSnapshot.Node,
        projectPath: String,
        paneSnapshotProvider: WorkspacePaneSnapshotProvider?,
        previousPaneMap: [String: WorkspacePaneRestoreSnapshot],
        snapshotFreshness: WorkspacePaneSnapshotFreshness
    ) -> WorkspacePaneTreeRestoreSnapshot.Node {
        switch node {
        case let .leaf(pane):
            let currentContext = paneSnapshotProvider?(projectPath, pane.paneId, snapshotFreshness)
            let previousPane = previousPaneMap[paneKey(projectPath: projectPath, paneID: pane.paneId)]
            var items = pane.items
            let selectedItemID = pane.selectedItemId ?? pane.selectedItem?.surfaceId
            if let selectedItemID,
               let selectedIndex = items.firstIndex(where: { $0.surfaceId == selectedItemID }) {
                let previousSelectedItem = previousPane?.item(for: selectedItemID) ?? previousPane?.selectedItem
                let currentItem = items[selectedIndex]
                items[selectedIndex] = WorkspacePaneItemRestoreSnapshot(
                    surfaceId: currentItem.surfaceId,
                    terminalSessionId: currentItem.terminalSessionId,
                    restoredWorkingDirectory: currentContext?.workingDirectory
                        ?? currentItem.restoredWorkingDirectory
                        ?? previousSelectedItem?.restoredWorkingDirectory,
                    restoredTitle: currentContext?.title
                        ?? currentItem.restoredTitle
                        ?? previousSelectedItem?.restoredTitle,
                    agentSummary: currentContext?.agentSummary
                        ?? currentItem.agentSummary
                        ?? previousSelectedItem?.agentSummary,
                    snapshotTextRef: previousSelectedItem?.snapshotTextRef ?? currentItem.snapshotTextRef,
                    snapshotText: currentContext?.snapshotText
                        ?? currentItem.snapshotText
                        ?? previousSelectedItem?.snapshotText
                )
            }
            return .leaf(
                WorkspacePaneRestoreSnapshot(
                    paneId: pane.paneId,
                    selectedItemId: selectedItemID,
                    items: items
                )
            )
        case let .split(split):
            return .split(
                WorkspaceSplitRestoreSnapshot(
                    direction: split.direction,
                    ratio: split.ratio,
                    left: enrich(
                        node: split.left,
                        projectPath: projectPath,
                        paneSnapshotProvider: paneSnapshotProvider,
                        previousPaneMap: previousPaneMap,
                        snapshotFreshness: snapshotFreshness
                    ),
                    right: enrich(
                        node: split.right,
                        projectPath: projectPath,
                        paneSnapshotProvider: paneSnapshotProvider,
                        previousPaneMap: previousPaneMap,
                        snapshotFreshness: snapshotFreshness
                    )
                )
            )
        }
    }

    private func makePreviousPaneMap() -> [String: WorkspacePaneRestoreSnapshot] {
        Dictionary(
            uniqueKeysWithValues: (lastSnapshot?.sessions ?? []).flatMap { session in
                session.tabs.flatMap { tab in
                    tab.tree.leaves.map { pane in
                        (paneKey(projectPath: session.projectPath, paneID: pane.paneId), pane)
                    }
                }
            }
        )
    }

    private func paneKey(projectPath: String, paneID: String) -> String {
        "\(projectPath)|\(paneID)"
    }
}
