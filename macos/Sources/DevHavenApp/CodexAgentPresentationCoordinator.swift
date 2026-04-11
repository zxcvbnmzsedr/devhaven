import Foundation
import DevHavenCore

@MainActor
final class CodexAgentPresentationCoordinator {
    struct EvaluationResult: Equatable {
        var runtimeState: CodexAgentDisplayStateRefresher.RuntimeState
        var overridesByProjectPath: [String: [String: WorkspaceAgentPresentationOverride]]
        var nextRefreshDeadline: Date?
    }

    private struct PaneKey: Hashable {
        let projectPath: String
        let paneID: String
    }

    private weak var viewModel: NativeAppViewModel?
    private weak var terminalStoreRegistry: WorkspaceTerminalStoreRegistry?
    private let artifactStore = CodexSessionArtifactStore()
    private var runtimeState = CodexAgentDisplayStateRefresher.RuntimeState()
    private var trackedPaneKeys: Set<PaneKey> = []
    private var snapshotsByPaneKey: [PaneKey: CodexAgentDisplaySnapshot] = [:]
    private var artifactsBySessionID: [String: CodexSessionArtifactSnapshot] = [:]
    private var lastOverridesByProjectPath: [String: [String: WorkspaceAgentPresentationOverride]] = [:]
    private var pendingDeadlineRefreshTask: Task<Void, Never>?

    func connect(
        viewModel: NativeAppViewModel,
        terminalStoreRegistry: WorkspaceTerminalStoreRegistry
    ) {
        if self.viewModel === viewModel,
           self.terminalStoreRegistry === terminalStoreRegistry {
            sync()
            return
        }
        self.viewModel = viewModel
        self.terminalStoreRegistry = terminalStoreRegistry
        artifactStore.onSnapshotsChange = { [weak self] snapshots in
            Task { @MainActor [weak self] in
                self?.handleArtifactsChange(snapshots)
            }
        }
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
        artifactStore.syncTrackedSessionIDs(Set(candidates.compactMap(\.signalSessionID)))
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
        artifactsBySessionID.removeAll()
        artifactStore.onSnapshotsChange = nil
        artifactStore.syncTrackedSessionIDs([])
        artifactStore.stop()
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

    private func handleArtifactsChange(
        _ snapshotsBySessionID: [String: CodexSessionArtifactSnapshot]
    ) {
        guard artifactsBySessionID != snapshotsBySessionID else {
            return
        }
        artifactsBySessionID = snapshotsBySessionID
        refreshPresentation()
    }

    private func refreshPresentation(
        for candidates: [WorkspaceAgentDisplayCandidate]? = nil
    ) {
        guard let viewModel else {
            return
        }

        let resolvedCandidates = candidates ?? viewModel.codexDisplayCandidates()
        let evaluation = Self.evaluatePresentation(
            for: resolvedCandidates,
            runtimeState: runtimeState,
            artifactProvider: { [artifactsBySessionID] sessionID in
                artifactsBySessionID[sessionID]
            },
            snapshotProvider: { [snapshotsByPaneKey] projectPath, paneID in
                snapshotsByPaneKey[PaneKey(projectPath: projectPath, paneID: paneID)]
            }
        )
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

    static func evaluatePresentation(
        for candidates: [WorkspaceAgentDisplayCandidate],
        runtimeState: CodexAgentDisplayStateRefresher.RuntimeState,
        now: Date = Date(),
        artifactProvider: (_ sessionID: String) -> CodexSessionArtifactSnapshot?,
        snapshotProvider: (_ projectPath: String, _ paneID: String) -> CodexAgentDisplaySnapshot?
    ) -> EvaluationResult {
        let evaluation = CodexAgentDisplayStateRefresher.evaluate(
            for: candidates,
            runtimeState: runtimeState,
            now: now
        ) { projectPath, paneID in
            guard let visibleSnapshot = snapshotProvider(projectPath, paneID) else {
                return nil
            }
            let sessionID = candidates.first(where: {
                $0.projectPath == projectPath && $0.paneID == paneID
            })?.signalSessionID
            let effectiveActivityAt = max(
                visibleSnapshot.lastActivityAt,
                sessionID.flatMap(artifactProvider)?.lastActivityAt ?? .distantPast
            )
            return CodexAgentDisplaySnapshot(
                recentTextWindow: visibleSnapshot.recentTextWindow,
                lastActivityAt: effectiveActivityAt
            )
        }

        return EvaluationResult(
            runtimeState: evaluation.runtimeState,
            overridesByProjectPath: mergedArtifactSummaries(
                onto: evaluation.overridesByProjectPath,
                for: candidates,
                artifactProvider: artifactProvider
            ),
            nextRefreshDeadline: evaluation.nextRefreshDeadline
        )
    }

    private static func mergedArtifactSummaries(
        onto overridesByProjectPath: [String: [String: WorkspaceAgentPresentationOverride]],
        for candidates: [WorkspaceAgentDisplayCandidate],
        artifactProvider: (_ sessionID: String) -> CodexSessionArtifactSnapshot?
    ) -> [String: [String: WorkspaceAgentPresentationOverride]] {
        var mergedOverrides = overridesByProjectPath

        for candidate in candidates {
            guard let sessionID = candidate.signalSessionID,
                  let artifactSnapshot = artifactProvider(sessionID),
                  let summary = artifactSnapshot.preferredSummary(for: candidate.signalState)
            else {
                continue
            }

            let existingOverride = mergedOverrides[candidate.projectPath]?[candidate.paneID]
            mergedOverrides[candidate.projectPath, default: [:]][candidate.paneID] =
                WorkspaceAgentPresentationOverride(
                    state: existingOverride?.state ?? candidate.signalState,
                    phase: existingOverride?.phase ?? candidate.signalPhase,
                    attention: existingOverride?.attention ?? candidate.signalAttention,
                    summary: summary
                )
        }

        return mergedOverrides
    }
}
