import Foundation
import DevHavenCore

@MainActor
enum CodexAgentDisplayStateRefresher {
    struct RuntimeState: Equatable {
        fileprivate var observationsByPaneKey: [PaneKey: Observation] = [:]
    }

    fileprivate struct PaneKey: Hashable {
        let projectPath: String
        let paneID: String
    }

    fileprivate struct Observation: Equatable {
        var lastRecentTextWindow: String
        var lastActivityAt: Date
    }

    private static let recentActivityWindow: TimeInterval = 2

    static func refresh(
        viewModel: NativeAppViewModel,
        runtimeState: RuntimeState,
        now: Date = Date(),
        snapshotProvider: (_ projectPath: String, _ paneID: String) -> CodexAgentDisplaySnapshot?
    ) -> RuntimeState {
        var mutableRuntimeState = runtimeState
        let overridesByProjectPath = presentationOverrides(
            for: viewModel.codexDisplayCandidates(),
            runtimeState: &mutableRuntimeState,
            now: now,
            snapshotProvider: snapshotProvider
        )
        viewModel.replaceWorkspaceAgentDisplayOverrides(overridesByProjectPath)
        return mutableRuntimeState
    }

    static func presentationOverrides(
        for candidates: [WorkspaceAgentDisplayCandidate],
        runtimeState: inout RuntimeState,
        now: Date = Date(),
        snapshotProvider: (_ projectPath: String, _ paneID: String) -> CodexAgentDisplaySnapshot?
    ) -> [String: [String: WorkspaceAgentPresentationOverride]] {
        let validPaneKeys = Set(
            candidates.map { PaneKey(projectPath: $0.projectPath, paneID: $0.paneID) }
        )
        runtimeState.observationsByPaneKey = runtimeState.observationsByPaneKey.filter {
            validPaneKeys.contains($0.key)
        }

        var overridesByProjectPath: [String: [String: WorkspaceAgentPresentationOverride]] = [:]

        for candidate in candidates {
            guard let snapshot = snapshotProvider(candidate.projectPath, candidate.paneID),
                  let recentTextWindow = normalizedVisibleText(snapshot.recentTextWindow)
            else {
                continue
            }

            let paneKey = PaneKey(projectPath: candidate.projectPath, paneID: candidate.paneID)
            var observation = runtimeState.observationsByPaneKey[paneKey]
                ?? Observation(
                    lastRecentTextWindow: recentTextWindow,
                    lastActivityAt: snapshot.lastActivityAt
                )

            if observation.lastRecentTextWindow != recentTextWindow
                || observation.lastActivityAt != snapshot.lastActivityAt {
                observation.lastRecentTextWindow = recentTextWindow
                observation.lastActivityAt = snapshot.lastActivityAt
            }
            runtimeState.observationsByPaneKey[paneKey] = observation

            let displayState = CodexAgentDisplayHeuristics.displayState(for: recentTextWindow)
            let isRecentlyActive = now.timeIntervalSince(snapshot.lastActivityAt) < recentActivityWindow

            switch candidate.signalState {
            case .waiting:
                guard displayState == .running || (displayState != .waiting && isRecentlyActive) else {
                    continue
                }
                overridesByProjectPath[candidate.projectPath, default: [:]][candidate.paneID] =
                    WorkspaceAgentPresentationOverride(state: .running, summary: nil)
            case .running:
                guard displayState == .waiting, !isRecentlyActive else {
                    continue
                }
                overridesByProjectPath[candidate.projectPath, default: [:]][candidate.paneID] =
                    WorkspaceAgentPresentationOverride(state: .waiting, summary: nil)
            default:
                continue
            }
        }

        return overridesByProjectPath
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
}
