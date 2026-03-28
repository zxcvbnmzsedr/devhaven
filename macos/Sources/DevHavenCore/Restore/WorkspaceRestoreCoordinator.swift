import Foundation

public typealias WorkspacePaneSnapshotProvider = @MainActor (_ projectPath: String, _ paneID: String) -> WorkspaceTerminalRestoreContext?

@MainActor
final class WorkspaceRestoreCoordinator {
    private let store: WorkspaceRestoreStore
    private let autosaveDelayNanoseconds: UInt64
    private var pendingAutosaveTask: Task<Void, Never>?
    private var lastSnapshot: WorkspaceRestoreSnapshot?

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
        paneSnapshotProvider: WorkspacePaneSnapshotProvider?
    ) {
        pendingAutosaveTask?.cancel()
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
            try? self.flushNow(
                activeProjectPath: activeProjectPath,
                selectedProjectPath: selectedProjectPath,
                sessions: sessions,
                paneSnapshotProvider: paneSnapshotProvider
            )
        }
    }

    func flushNow(
        activeProjectPath: String?,
        selectedProjectPath: String?,
        sessions: [OpenWorkspaceSessionState],
        paneSnapshotProvider: WorkspacePaneSnapshotProvider?
    ) throws {
        pendingAutosaveTask?.cancel()
        pendingAutosaveTask = nil

        let snapshot = captureSnapshot(
            activeProjectPath: activeProjectPath,
            selectedProjectPath: selectedProjectPath,
            sessions: sessions,
            paneSnapshotProvider: paneSnapshotProvider
        )

        guard !snapshot.isEmpty else {
            try store.removeSnapshot()
            lastSnapshot = nil
            return
        }

        try store.saveSnapshot(snapshot)
        lastSnapshot = loadSnapshot()
    }

    private func captureSnapshot(
        activeProjectPath: String?,
        selectedProjectPath: String?,
        sessions: [OpenWorkspaceSessionState],
        paneSnapshotProvider: WorkspacePaneSnapshotProvider?
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
                        previousPaneMap: previousPaneMap
                    ),
                    zoomedPaneId: tab.tree.zoomedPaneId
                )
                return tab
            }
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
            pane.snapshotText = store.loadPaneText(for: pane.snapshotTextRef)
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
        previousPaneMap: [String: WorkspacePaneRestoreSnapshot]
    ) -> WorkspacePaneTreeRestoreSnapshot.Node {
        switch node {
        case let .leaf(pane):
            let currentContext = paneSnapshotProvider?(projectPath, pane.paneId)
            let previousPane = previousPaneMap[paneKey(projectPath: projectPath, paneID: pane.paneId)]
            return .leaf(
                WorkspacePaneRestoreSnapshot(
                    paneId: pane.paneId,
                    surfaceId: pane.surfaceId,
                    terminalSessionId: pane.terminalSessionId,
                    restoredWorkingDirectory: currentContext?.workingDirectory ?? previousPane?.restoredWorkingDirectory,
                    restoredTitle: currentContext?.title ?? previousPane?.restoredTitle,
                    agentSummary: currentContext?.agentSummary ?? previousPane?.agentSummary,
                    snapshotTextRef: previousPane?.snapshotTextRef,
                    snapshotText: currentContext?.snapshotText ?? previousPane?.snapshotText
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
                        previousPaneMap: previousPaneMap
                    ),
                    right: enrich(
                        node: split.right,
                        projectPath: projectPath,
                        paneSnapshotProvider: paneSnapshotProvider,
                        previousPaneMap: previousPaneMap
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
