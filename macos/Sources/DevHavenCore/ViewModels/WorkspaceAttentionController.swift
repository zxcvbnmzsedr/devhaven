import Foundation

@MainActor
final class WorkspaceAttentionController {
    private let normalizePath: @MainActor (String) -> String
    private let openProjectPaths: @MainActor () -> [String]
    private let activeProjectPath: @MainActor () -> String?
    private let notificationsEnabled: @MainActor () -> Bool
    private let workspaceSession: @MainActor (String?) -> OpenWorkspaceSessionState?
    private let workspaceController: @MainActor (String) -> GhosttyWorkspaceController?
    private let resolvedPresentedTabSelection: @MainActor (String, GhosttyWorkspaceController?) -> WorkspacePresentedTabSelection?
    private let isWorkspacePaneCurrentlyFocused: @MainActor (String, String, String) -> Bool
    private let currentPaneIDForSignal: @MainActor (WorkspaceAgentSessionSignal) -> String?
    private let attentionStateByProjectPath: @MainActor () -> [String: WorkspaceAttentionState]
    private let setAttentionStateByProjectPath: @MainActor ([String: WorkspaceAttentionState]) -> Void
    private let agentDisplayOverridesByProjectPath: @MainActor () -> [String: [String: WorkspaceAgentPresentationOverride]]
    private let setAgentDisplayOverridesByProjectPath: @MainActor ([String: [String: WorkspaceAgentPresentationOverride]]) -> Void
    private let reportError: @MainActor (String?) -> Void
    private let codexDisplayCandidatesDidChange: @MainActor ([WorkspaceAgentDisplayCandidate]) -> Void
    private let agentSignalStore: WorkspaceAgentSignalStore

    private var isAgentSignalObservationStarted = false
    private var lastAppliedAgentSignalSnapshotsByTerminalSessionID: [String: WorkspaceAgentSessionSignal] = [:]
    private var lastAppliedAgentSignalProjectPaths: Set<String> = []
    private var cachedCodexDisplayCandidates: [WorkspaceAgentDisplayCandidate] = []

    init(
        normalizePath: @escaping @MainActor (String) -> String,
        openProjectPaths: @escaping @MainActor () -> [String],
        activeProjectPath: @escaping @MainActor () -> String?,
        notificationsEnabled: @escaping @MainActor () -> Bool,
        workspaceSession: @escaping @MainActor (String?) -> OpenWorkspaceSessionState?,
        workspaceController: @escaping @MainActor (String) -> GhosttyWorkspaceController?,
        resolvedPresentedTabSelection: @escaping @MainActor (String, GhosttyWorkspaceController?) -> WorkspacePresentedTabSelection?,
        isWorkspacePaneCurrentlyFocused: @escaping @MainActor (String, String, String) -> Bool,
        currentPaneIDForSignal: @escaping @MainActor (WorkspaceAgentSessionSignal) -> String?,
        attentionStateByProjectPath: @escaping @MainActor () -> [String: WorkspaceAttentionState],
        setAttentionStateByProjectPath: @escaping @MainActor ([String: WorkspaceAttentionState]) -> Void,
        agentDisplayOverridesByProjectPath: @escaping @MainActor () -> [String: [String: WorkspaceAgentPresentationOverride]],
        setAgentDisplayOverridesByProjectPath: @escaping @MainActor ([String: [String: WorkspaceAgentPresentationOverride]]) -> Void,
        reportError: @escaping @MainActor (String?) -> Void,
        codexDisplayCandidatesDidChange: @escaping @MainActor ([WorkspaceAgentDisplayCandidate]) -> Void,
        agentSignalStore: WorkspaceAgentSignalStore
    ) {
        self.normalizePath = normalizePath
        self.openProjectPaths = openProjectPaths
        self.activeProjectPath = activeProjectPath
        self.notificationsEnabled = notificationsEnabled
        self.workspaceSession = workspaceSession
        self.workspaceController = workspaceController
        self.resolvedPresentedTabSelection = resolvedPresentedTabSelection
        self.isWorkspacePaneCurrentlyFocused = isWorkspacePaneCurrentlyFocused
        self.currentPaneIDForSignal = currentPaneIDForSignal
        self.attentionStateByProjectPath = attentionStateByProjectPath
        self.setAttentionStateByProjectPath = setAttentionStateByProjectPath
        self.agentDisplayOverridesByProjectPath = agentDisplayOverridesByProjectPath
        self.setAgentDisplayOverridesByProjectPath = setAgentDisplayOverridesByProjectPath
        self.reportError = reportError
        self.codexDisplayCandidatesDidChange = codexDisplayCandidatesDidChange
        self.agentSignalStore = agentSignalStore
    }

    func workspaceAttentionState(for projectPath: String) -> WorkspaceAttentionState? {
        attentionStateByProjectPath()[normalizePath(projectPath)]
    }

    func recordWorkspaceNotification(
        projectPath: String,
        tabID: String,
        paneID: String,
        title: String,
        body: String,
        createdAt: Date = Date()
    ) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !(trimmedTitle.isEmpty && trimmedBody.isEmpty),
              notificationsEnabled(),
              let session = workspaceSession(projectPath)
        else {
            return
        }

        let normalizedProjectPath = normalizePath(projectPath)
        var states = attentionStateByProjectPath()
        var attention = states[normalizedProjectPath] ?? WorkspaceAttentionState()
        attention.appendNotification(
            WorkspaceTerminalNotification(
                projectPath: projectPath,
                rootProjectPath: session.rootProjectPath,
                workspaceId: session.controller.workspaceId,
                tabId: tabID,
                paneId: paneID,
                title: trimmedTitle,
                body: trimmedBody,
                createdAt: createdAt,
                isRead: isWorkspacePaneCurrentlyFocused(projectPath, tabID, paneID)
            )
        )
        states[normalizedProjectPath] = attention
        setAttentionStateByProjectPath(states)
    }

    func updateWorkspaceTaskStatus(
        projectPath: String,
        paneID: String,
        status: WorkspaceTaskStatus
    ) {
        let normalizedProjectPath = normalizePath(projectPath)
        var states = attentionStateByProjectPath()
        var attention = states[normalizedProjectPath] ?? WorkspaceAttentionState()
        let previousAttention = attention
        attention.setTaskStatus(status, for: paneID)
        guard attention != previousAttention else {
            return
        }
        states[normalizedProjectPath] = attention
        setAttentionStateByProjectPath(states)
    }

    func recordAgentSignal(_ signal: WorkspaceAgentSessionSignal) {
        let normalizedProjectPath = normalizePath(signal.projectPath)
        guard Set(openProjectPaths()).contains(normalizedProjectPath) else {
            return
        }
        let normalizedSignal = normalizedAgentSignal(signal)
        var states = attentionStateByProjectPath()
        var attention = states[normalizedProjectPath] ?? WorkspaceAttentionState()
        let previousAttention = attention
        applyAgentSignal(normalizedSignal, to: &attention)
        guard attention != previousAttention else {
            return
        }
        invalidateAppliedAgentSignalCache()
        states[normalizedSignal.projectPath] = attention
        setAttentionStateByProjectPath(states)
    }

    func clearAgentSignal(projectPath: String, paneID: String) {
        let normalizedProjectPath = normalizePath(projectPath)
        var states = attentionStateByProjectPath()
        guard var attention = states[normalizedProjectPath] else {
            return
        }
        let previousAttention = attention
        attention.clearAgentState(for: paneID)
        guard attention != previousAttention else {
            return
        }
        invalidateAppliedAgentSignalCache()
        states[normalizedProjectPath] = attention
        setAttentionStateByProjectPath(states)
    }

    func startWorkspaceAgentSignalObservation() {
        guard !isAgentSignalObservationStarted else {
            refreshWorkspaceAgentSignals()
            return
        }
        agentSignalStore.onSignalsChange = { [weak self] snapshots in
            Task { @MainActor in
                self?.applyAgentSignalSnapshots(snapshots)
            }
        }
        do {
            try agentSignalStore.start()
            isAgentSignalObservationStarted = true
            applyAgentSignalSnapshots(agentSignalStore.currentSnapshots)
        } catch {
            reportError((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func stopWorkspaceAgentSignalObservation() {
        guard isAgentSignalObservationStarted else {
            return
        }
        agentSignalStore.stop()
        isAgentSignalObservationStarted = false
        invalidateAppliedAgentSignalCache()
    }

    func refreshWorkspaceAgentSignals() {
        applyAgentSignalSnapshots(agentSignalStore.currentSnapshots)
    }

    func codexDisplayCandidates() -> [WorkspaceAgentDisplayCandidate] {
        refreshCodexDisplayCandidates()
        return cachedCodexDisplayCandidates
    }

    func refreshCodexDisplayCandidates() {
        let sortedCandidates = WorkspaceAgentDisplayCandidate.observationStableSorted(
            computeCodexDisplayCandidates()
        )
        guard cachedCodexDisplayCandidates != sortedCandidates else {
            return
        }
        cachedCodexDisplayCandidates = sortedCandidates
        codexDisplayCandidatesDidChange(sortedCandidates)
    }

    func replaceWorkspaceAgentDisplayOverrides(
        _ overridesByProjectPath: [String: [String: WorkspaceAgentPresentationOverride]]
    ) {
        let filteredOverrides = filteredWorkspaceAgentDisplayOverrides(overridesByProjectPath)
        guard agentDisplayOverridesByProjectPath() != filteredOverrides else {
            return
        }
        setAgentDisplayOverridesByProjectPath(filteredOverrides)
    }

    func markWorkspaceNotificationsRead(projectPath: String, paneID: String) {
        let normalizedProjectPath = normalizePath(projectPath)
        var states = attentionStateByProjectPath()
        guard var attention = states[normalizedProjectPath] else {
            return
        }
        attention.markNotificationsRead(for: paneID)
        states[normalizedProjectPath] = attention
        setAttentionStateByProjectPath(states)
    }

    func markWorkspaceNotificationRead(projectPath: String, notificationID: UUID) {
        let normalizedProjectPath = normalizePath(projectPath)
        var states = attentionStateByProjectPath()
        guard var attention = states[normalizedProjectPath] else {
            return
        }
        attention.markNotificationRead(id: notificationID)
        states[normalizedProjectPath] = attention
        setAttentionStateByProjectPath(states)
    }

    func agentDisplayOverridesByPaneID(for projectPath: String) -> [String: WorkspaceAgentPresentationOverride] {
        agentDisplayOverridesByProjectPath()[normalizePath(projectPath)] ?? [:]
    }

    func syncAttentionStateWithOpenSessions() {
        let activePaths = Set(openProjectPaths())

        let filteredAttention = attentionStateByProjectPath().filter { activePaths.contains($0.key) }
        if attentionStateByProjectPath() != filteredAttention {
            setAttentionStateByProjectPath(filteredAttention)
        }

        let filteredOverrides = agentDisplayOverridesByProjectPath().filter { activePaths.contains($0.key) }
        if agentDisplayOverridesByProjectPath() != filteredOverrides {
            setAgentDisplayOverridesByProjectPath(filteredOverrides)
        }

        if isAgentSignalObservationStarted {
            applyAgentSignalSnapshots(agentSignalStore.currentSnapshots)
        } else {
            refreshCodexDisplayCandidates()
        }
    }

    private func computeCodexDisplayCandidates() -> [WorkspaceAgentDisplayCandidate] {
        guard let activeWorkspaceProjectPath = activeProjectPath(),
              Set(openProjectPaths()).contains(normalizePath(activeWorkspaceProjectPath)),
              let controller = workspaceController(activeWorkspaceProjectPath),
              case let .terminal(selectedTerminalTabID)? = resolvedPresentedTabSelection(
                activeWorkspaceProjectPath,
                controller
              ),
              let selectedTab = controller.tabs.first(where: { $0.id == selectedTerminalTabID }),
              let attention = workspaceAttentionState(for: activeWorkspaceProjectPath)
        else {
            return []
        }

        let visiblePaneIDs = Set(selectedTab.leaves.map(\.id))
        return attention.agentStateByPaneID.compactMap { entry -> WorkspaceAgentDisplayCandidate? in
            let (paneID, state) = entry
            guard visiblePaneIDs.contains(paneID),
                  (state == .running || state == .waiting),
                  attention.agentKindByPaneID[paneID] == .codex
            else {
                return nil
            }
            return WorkspaceAgentDisplayCandidate(
                projectPath: activeWorkspaceProjectPath,
                paneID: paneID,
                signalSessionID: attention.agentSessionIDByPaneID[paneID],
                signalState: state,
                signalPhase: attention.agentPhaseByPaneID[paneID],
                signalAttention: attention.agentAttentionByPaneID[paneID],
                signalUpdatedAt: attention.agentUpdatedAtByPaneID[paneID]
            )
        }
    }

    private func applyAgentSignalSnapshots(_ snapshots: [String: WorkspaceAgentSessionSignal]) {
        let normalizedSnapshots = normalizedAgentSignalSnapshots(snapshots)
        let openPaths = Set(openProjectPaths())
        guard lastAppliedAgentSignalProjectPaths != openPaths ||
                lastAppliedAgentSignalSnapshotsByTerminalSessionID != normalizedSnapshots
        else {
            return
        }

        let previousSnapshots = lastAppliedAgentSignalSnapshotsByTerminalSessionID
        var nextAttentionStateByProjectPath = attentionStateByProjectPath().filter { openPaths.contains($0.key) }

        for (terminalSessionID, previousSignal) in previousSnapshots {
            guard openPaths.contains(previousSignal.projectPath) else {
                continue
            }
            if let currentSignal = snapshots[terminalSessionID],
               currentSignal.projectPath == previousSignal.projectPath,
               currentSignal.paneId == previousSignal.paneId {
                continue
            }
            guard var attention = nextAttentionStateByProjectPath[previousSignal.projectPath] else {
                continue
            }
            attention.clearAgentState(for: previousSignal.paneId)
            nextAttentionStateByProjectPath[previousSignal.projectPath] = attention
        }

        for (terminalSessionID, signal) in normalizedSnapshots where openPaths.contains(signal.projectPath) {
            if previousSnapshots[terminalSessionID] == signal {
                continue
            }
            var attention = nextAttentionStateByProjectPath[signal.projectPath] ?? WorkspaceAttentionState()
            applyAgentSignal(signal, to: &attention)
            nextAttentionStateByProjectPath[signal.projectPath] = attention
        }

        if attentionStateByProjectPath() != nextAttentionStateByProjectPath {
            setAttentionStateByProjectPath(nextAttentionStateByProjectPath)
        }
        lastAppliedAgentSignalProjectPaths = openPaths
        lastAppliedAgentSignalSnapshotsByTerminalSessionID = normalizedSnapshots
        pruneWorkspaceAgentDisplayOverrides()
    }

    private func invalidateAppliedAgentSignalCache() {
        lastAppliedAgentSignalProjectPaths = []
        lastAppliedAgentSignalSnapshotsByTerminalSessionID = [:]
    }

    private func pruneWorkspaceAgentDisplayOverrides() {
        let filteredOverrides = filteredWorkspaceAgentDisplayOverrides(agentDisplayOverridesByProjectPath())
        guard agentDisplayOverridesByProjectPath() != filteredOverrides else {
            return
        }
        setAgentDisplayOverridesByProjectPath(filteredOverrides)
    }

    private func filteredWorkspaceAgentDisplayOverrides(
        _ overridesByProjectPath: [String: [String: WorkspaceAgentPresentationOverride]]
    ) -> [String: [String: WorkspaceAgentPresentationOverride]] {
        guard !overridesByProjectPath.isEmpty else {
            return [:]
        }

        let validPaneIDsByProjectPath = Dictionary(
            grouping: codexDisplayCandidates(),
            by: \.projectPath
        ).mapValues { Set($0.map(\.paneID)) }

        return overridesByProjectPath.reduce(into: [:]) { result, entry in
            guard let validPaneIDs = validPaneIDsByProjectPath[entry.key] else {
                return
            }
            let filteredOverrides = entry.value.filter { validPaneIDs.contains($0.key) }
            guard !filteredOverrides.isEmpty else {
                return
            }
            result[entry.key] = filteredOverrides
        }
    }

    private func applyAgentSignal(
        _ signal: WorkspaceAgentSessionSignal,
        to attention: inout WorkspaceAttentionState
    ) {
        attention.setAgentState(
            signal.effectiveState,
            kind: signal.agentKind,
            sessionID: signal.sessionId,
            phase: signal.effectivePhase,
            attention: signal.effectiveAttention,
            summary: signal.summary,
            updatedAt: signal.updatedAt,
            for: signal.paneId
        )
    }

    private func normalizedAgentSignalSnapshots(
        _ snapshots: [String: WorkspaceAgentSessionSignal]
    ) -> [String: WorkspaceAgentSessionSignal] {
        snapshots.reduce(into: [:]) { partialResult, entry in
            partialResult[entry.key] = normalizedAgentSignal(entry.value)
        }
    }

    private func normalizedAgentSignal(
        _ signal: WorkspaceAgentSessionSignal
    ) -> WorkspaceAgentSessionSignal {
        var normalized = signal
        normalized.projectPath = normalizePath(signal.projectPath)
        if let resolvedPaneID = currentPaneIDForSignal(signal),
           resolvedPaneID != signal.paneId {
            normalized.paneId = resolvedPaneID
        }
        return normalized
    }
}
