import Foundation
import DevHavenCore

@MainActor
enum CodexAgentDisplayStateRefresher {
    struct RuntimeState: Equatable {
        fileprivate var observationsByPaneKey: [PaneKey: Observation] = [:]
    }

    struct EvaluationResult: Equatable {
        var runtimeState: RuntimeState
        var overridesByProjectPath: [String: [String: WorkspaceAgentPresentationOverride]]
        var nextRefreshDeadline: Date?
    }

    fileprivate struct PaneKey: Hashable {
        let projectPath: String
        let paneID: String
    }

    fileprivate struct Observation: Equatable {
        var lastRecentTextWindow: String
        var lastActivityAt: Date
    }

    static let recentActivityWindow: TimeInterval = 2
    static let minimumSignalPriorityWindow: TimeInterval = 1

    static func refresh(
        viewModel: NativeAppViewModel,
        runtimeState: RuntimeState,
        now: Date = Date(),
        snapshotProvider: (_ projectPath: String, _ paneID: String) -> CodexAgentDisplaySnapshot?
    ) -> RuntimeState {
        let evaluation = evaluate(
            for: viewModel.codexDisplayCandidates(),
            runtimeState: runtimeState,
            now: now,
            snapshotProvider: snapshotProvider
        )
        viewModel.replaceWorkspaceAgentDisplayOverrides(evaluation.overridesByProjectPath)
        return evaluation.runtimeState
    }

    static func evaluate(
        for candidates: [WorkspaceAgentDisplayCandidate],
        runtimeState: RuntimeState,
        now: Date = Date(),
        snapshotProvider: (_ projectPath: String, _ paneID: String) -> CodexAgentDisplaySnapshot?
    ) -> EvaluationResult {
        var mutableRuntimeState = runtimeState
        let validPaneKeys = Set(
            candidates.map { PaneKey(projectPath: $0.projectPath, paneID: $0.paneID) }
        )
        mutableRuntimeState.observationsByPaneKey = mutableRuntimeState.observationsByPaneKey.filter {
            validPaneKeys.contains($0.key)
        }

        var overridesByProjectPath: [String: [String: WorkspaceAgentPresentationOverride]] = [:]
        var nextRefreshDeadline: Date?

        for candidate in candidates {
            guard let snapshot = snapshotProvider(candidate.projectPath, candidate.paneID),
                  let recentTextWindow = normalizedVisibleText(snapshot.recentTextWindow)
            else {
                continue
            }

            if candidate.signalAttention?.requiresUserAction == true,
               !hasPostSignalActivity(snapshot: snapshot, candidate: candidate) {
                continue
            }

            if let signalUpdatedAt = candidate.signalUpdatedAt {
                let signalPriorityDeadline = signalUpdatedAt.addingTimeInterval(minimumSignalPriorityWindow)
                if now < signalPriorityDeadline {
                    nextRefreshDeadline = earliestDeadline(nextRefreshDeadline, signalPriorityDeadline)
                    continue
                }
            }

            let paneKey = PaneKey(projectPath: candidate.projectPath, paneID: candidate.paneID)
            var observation = mutableRuntimeState.observationsByPaneKey[paneKey]
                ?? Observation(
                    lastRecentTextWindow: recentTextWindow,
                    lastActivityAt: snapshot.lastActivityAt
                )

            if observation.lastRecentTextWindow != recentTextWindow
                || observation.lastActivityAt != snapshot.lastActivityAt {
                observation.lastRecentTextWindow = recentTextWindow
                observation.lastActivityAt = snapshot.lastActivityAt
            }
            mutableRuntimeState.observationsByPaneKey[paneKey] = observation

            let displayState = CodexAgentDisplayHeuristics.displayState(for: recentTextWindow)
            let refreshDeadline = snapshot.lastActivityAt.addingTimeInterval(recentActivityWindow)
            let isRecentlyActive = now < refreshDeadline

            switch candidate.signalState {
            case .waiting:
                if displayState == .running {
                    overridesByProjectPath[candidate.projectPath, default: [:]][candidate.paneID] =
                        runningOverride(for: candidate)
                } else if displayState != .waiting, isRecentlyActive {
                    overridesByProjectPath[candidate.projectPath, default: [:]][candidate.paneID] =
                        runningOverride(for: candidate)
                    nextRefreshDeadline = earliestDeadline(nextRefreshDeadline, refreshDeadline)
                }
            case .running:
                guard displayState == .waiting else {
                    continue
                }
                if isRecentlyActive {
                    nextRefreshDeadline = earliestDeadline(nextRefreshDeadline, refreshDeadline)
                } else {
                    overridesByProjectPath[candidate.projectPath, default: [:]][candidate.paneID] =
                        waitingOverride()
                }
            default:
                continue
            }
        }

        return EvaluationResult(
            runtimeState: mutableRuntimeState,
            overridesByProjectPath: overridesByProjectPath,
            nextRefreshDeadline: nextRefreshDeadline
        )
    }

    static func presentationOverrides(
        for candidates: [WorkspaceAgentDisplayCandidate],
        runtimeState: inout RuntimeState,
        now: Date = Date(),
        snapshotProvider: (_ projectPath: String, _ paneID: String) -> CodexAgentDisplaySnapshot?
    ) -> [String: [String: WorkspaceAgentPresentationOverride]] {
        let evaluation = evaluate(
            for: candidates,
            runtimeState: runtimeState,
            now: now,
            snapshotProvider: snapshotProvider
        )
        runtimeState = evaluation.runtimeState
        return evaluation.overridesByProjectPath
    }

    private static func normalizedVisibleText(_ visibleText: String?) -> String? {
        guard let visibleText else {
            return nil
        }
        let trimmedText = visibleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return nil
        }
        return trimmedText
    }

    private static func earliestDeadline(_ lhs: Date?, _ rhs: Date) -> Date {
        guard let lhs else {
            return rhs
        }
        return min(lhs, rhs)
    }

    private static func hasPostSignalActivity(
        snapshot: CodexAgentDisplaySnapshot,
        candidate: WorkspaceAgentDisplayCandidate
    ) -> Bool {
        guard let signalUpdatedAt = candidate.signalUpdatedAt else {
            return true
        }
        return snapshot.lastActivityAt > signalUpdatedAt
    }

    private static func runningOverride(
        for candidate: WorkspaceAgentDisplayCandidate
    ) -> WorkspaceAgentPresentationOverride {
        let phase: WorkspaceAgentPhase
        switch candidate.signalPhase {
        case .launching?, .thinking?, .runningTool?:
            phase = candidate.signalPhase ?? .thinking
        default:
            phase = .thinking
        }

        return WorkspaceAgentPresentationOverride(
            state: .running,
            phase: phase,
            attention: WorkspaceAgentAttentionRequirement.none,
            summary: nil
        )
    }

    private static func waitingOverride() -> WorkspaceAgentPresentationOverride {
        WorkspaceAgentPresentationOverride(
            state: .waiting,
            phase: .awaitingInput,
            attention: .input,
            summary: nil
        )
    }
}
