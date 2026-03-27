import Foundation
import DevHavenCore

@MainActor
final class CodexAgentPresentationCoordinator {
    private struct PaneKey: Hashable {
        let projectPath: String
        let paneID: String
    }

    private weak var viewModel: NativeAppViewModel?
    private weak var terminalStoreRegistry: WorkspaceTerminalStoreRegistry?
    private var runtimeState = CodexAgentDisplayStateRefresher.RuntimeState()
    private var trackedPaneKeys: Set<PaneKey> = []
    private var snapshotsByPaneKey: [PaneKey: CodexAgentDisplaySnapshot] = [:]
    private var lastOverridesByProjectPath: [String: [String: WorkspaceAgentPresentationOverride]] = [:]
    private var pendingDeadlineRefreshTask: Task<Void, Never>?

    func connect(
        viewModel: NativeAppViewModel,
        terminalStoreRegistry: WorkspaceTerminalStoreRegistry
    ) {
        self.viewModel = viewModel
        self.terminalStoreRegistry = terminalStoreRegistry
        terminalStoreRegistry.setCodexDisplayModelCreatedObserver { [weak self] projectPath, paneID, model in
            Task { @MainActor [weak self] in
                self?.handleMaterializedModel(
                    model,
                    for: PaneKey(projectPath: projectPath, paneID: paneID)
                )
            }
        }
        sync()
    }

    func sync() {
        guard let viewModel else {
            return
        }

        let candidates = viewModel.codexDisplayCandidates()
        let nextPaneKeys = Set(
            candidates.map { PaneKey(projectPath: $0.projectPath, paneID: $0.paneID) }
        )
        let removedPaneKeys = trackedPaneKeys.subtracting(nextPaneKeys)
        for paneKey in removedPaneKeys {
            terminalStoreRegistry?
                .modelIfLoaded(for: paneKey.projectPath, paneID: paneKey.paneID)?
                .setCodexDisplaySnapshotObserver(nil)
            snapshotsByPaneKey.removeValue(forKey: paneKey)
        }

        let trackedPaneIDsByProjectPath = Dictionary(
            grouping: candidates,
            by: \.projectPath
        ).mapValues { Set($0.map(\.paneID)) }
        terminalStoreRegistry?.syncCodexDisplayTracking(trackedPaneIDsByProjectPath)

        trackedPaneKeys = nextPaneKeys
        for paneKey in nextPaneKeys {
            guard let model = terminalStoreRegistry?.modelIfLoaded(
                for: paneKey.projectPath,
                paneID: paneKey.paneID
            ) else {
                snapshotsByPaneKey.removeValue(forKey: paneKey)
                continue
            }
            bindSnapshotObserverIfNeeded(to: model, paneKey: paneKey)
        }

        refreshPresentation(for: candidates)
    }

    func disconnect() {
        pendingDeadlineRefreshTask?.cancel()
        pendingDeadlineRefreshTask = nil
        for paneKey in trackedPaneKeys {
            terminalStoreRegistry?
                .modelIfLoaded(for: paneKey.projectPath, paneID: paneKey.paneID)?
                .setCodexDisplaySnapshotObserver(nil)
        }
        terminalStoreRegistry?.setCodexDisplayModelCreatedObserver(nil)
        terminalStoreRegistry?.syncCodexDisplayTracking([:])
        trackedPaneKeys.removeAll()
        snapshotsByPaneKey.removeAll()
        runtimeState = CodexAgentDisplayStateRefresher.RuntimeState()

        if !lastOverridesByProjectPath.isEmpty {
            lastOverridesByProjectPath = [:]
            viewModel?.replaceWorkspaceAgentDisplayOverrides([:])
        }

        viewModel = nil
        terminalStoreRegistry = nil
    }

    private func handleMaterializedModel(
        _ model: GhosttySurfaceHostModel,
        for paneKey: PaneKey
    ) {
        guard trackedPaneKeys.contains(paneKey) else {
            return
        }
        bindSnapshotObserverIfNeeded(to: model, paneKey: paneKey)
    }

    private func bindSnapshotObserverIfNeeded(
        to model: GhosttySurfaceHostModel,
        paneKey: PaneKey
    ) {
        model.setCodexDisplaySnapshotObserver { [weak self] snapshot in
            Task { @MainActor [weak self] in
                self?.handleSnapshot(snapshot, for: paneKey)
            }
        }
    }

    private func handleSnapshot(
        _ snapshot: CodexAgentDisplaySnapshot?,
        for paneKey: PaneKey
    ) {
        guard trackedPaneKeys.contains(paneKey) else {
            return
        }
        if snapshotsByPaneKey[paneKey] == snapshot {
            return
        }
        snapshotsByPaneKey[paneKey] = snapshot
        refreshPresentation()
    }

    private func refreshPresentation(
        for candidates: [WorkspaceAgentDisplayCandidate]? = nil
    ) {
        guard let viewModel else {
            return
        }

        let resolvedCandidates = candidates ?? viewModel.codexDisplayCandidates()
        let evaluation = CodexAgentDisplayStateRefresher.evaluate(
            for: resolvedCandidates,
            runtimeState: runtimeState
        ) { [snapshotsByPaneKey] projectPath, paneID in
            snapshotsByPaneKey[PaneKey(projectPath: projectPath, paneID: paneID)]
        }

        runtimeState = evaluation.runtimeState
        scheduleDeadlineRefresh(at: evaluation.nextRefreshDeadline)
        guard lastOverridesByProjectPath != evaluation.overridesByProjectPath else {
            return
        }
        lastOverridesByProjectPath = evaluation.overridesByProjectPath
        viewModel.replaceWorkspaceAgentDisplayOverrides(evaluation.overridesByProjectPath)
    }

    private func scheduleDeadlineRefresh(at deadline: Date?) {
        pendingDeadlineRefreshTask?.cancel()
        pendingDeadlineRefreshTask = nil

        guard let deadline else {
            return
        }

        let interval = max(0, deadline.timeIntervalSinceNow) + 0.05
        pendingDeadlineRefreshTask = Task { @MainActor [weak self] in
            if interval > 0 {
                try? await ContinuousClock().sleep(for: .seconds(interval))
            } else {
                await Task.yield()
            }
            guard !Task.isCancelled else {
                return
            }
            self?.pendingDeadlineRefreshTask = nil
            self?.refreshPresentation()
        }
    }
}
