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
        var lastVisibleText: String
        var lastChangedAt: Date
    }

    private static let recentActivityWindow: TimeInterval = 2

    static func refresh(
        viewModel: NativeAppViewModel,
        runtimeState: RuntimeState,
        now: Date = Date(),
        visibleTextProvider: (_ projectPath: String, _ paneID: String) -> String?
    ) -> RuntimeState {
        var mutableRuntimeState = runtimeState
        let overridesByProjectPath = presentationOverrides(
            for: viewModel.codexDisplayCandidates(),
            runtimeState: &mutableRuntimeState,
            now: now,
            visibleTextProvider: visibleTextProvider
        )
        viewModel.replaceWorkspaceAgentDisplayOverrides(overridesByProjectPath)
        return mutableRuntimeState
    }

    static func presentationOverrides(
        for candidates: [WorkspaceAgentDisplayCandidate],
        runtimeState: inout RuntimeState,
        now: Date = Date(),
        visibleTextProvider: (_ projectPath: String, _ paneID: String) -> String?
    ) -> [String: [String: WorkspaceAgentPresentationOverride]] {
        let validPaneKeys = Set(
            candidates.map { PaneKey(projectPath: $0.projectPath, paneID: $0.paneID) }
        )
        runtimeState.observationsByPaneKey = runtimeState.observationsByPaneKey.filter {
            validPaneKeys.contains($0.key)
        }

        var overridesByProjectPath: [String: [String: WorkspaceAgentPresentationOverride]] = [:]

        for candidate in candidates {
            guard let visibleText = normalizedVisibleText(
                visibleTextProvider(candidate.projectPath, candidate.paneID)
            ) else {
                continue
            }

            let paneKey = PaneKey(projectPath: candidate.projectPath, paneID: candidate.paneID)
            var observation = runtimeState.observationsByPaneKey[paneKey]
                ?? Observation(lastVisibleText: visibleText, lastChangedAt: now)

            if observation.lastVisibleText != visibleText {
                observation.lastVisibleText = visibleText
                observation.lastChangedAt = now
            }
            runtimeState.observationsByPaneKey[paneKey] = observation

            let displayState = CodexAgentDisplayHeuristics.displayState(for: visibleText)
            let isRecentlyActive = now.timeIntervalSince(observation.lastChangedAt) < recentActivityWindow

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
