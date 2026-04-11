import XCTest
import DevHavenCore
@testable import DevHavenApp

@MainActor
final class CodexAgentPresentationCoordinatorTests: XCTestCase {
    func testEvaluatePresentationMergesArtifactSummaryIntoOverrides() {
        let candidate = WorkspaceAgentDisplayCandidate(
            projectPath: "/tmp/project",
            paneID: "pane-1",
            signalSessionID: "session-1",
            signalState: .waiting,
            signalPhase: .awaitingInput,
            signalUpdatedAt: Date(timeIntervalSinceReferenceDate: 100)
        )
        let artifact = CodexSessionArtifactSnapshot(
            sessionID: "session-1",
            threadTitle: "继续推进 DevHaven Codex 监听",
            lastActivityAt: Date(timeIntervalSinceReferenceDate: 101),
            lastAssistantSummary: "我已经把监听主链接起来了。",
            lastTaskCompleteSummary: "实现完成，等待你验收。",
            lastTaskCompleteAt: Date(timeIntervalSinceReferenceDate: 101),
            sessionFileURL: nil
        )

        let evaluation = CodexAgentPresentationCoordinator.evaluatePresentation(
            for: [candidate],
            runtimeState: .init(),
            now: Date(timeIntervalSinceReferenceDate: 105),
            artifactProvider: { sessionID in
                sessionID == "session-1" ? artifact : nil
            },
            snapshotProvider: { _, _ in nil }
        )

        XCTAssertEqual(
            evaluation.overridesByProjectPath["/tmp/project"]?["pane-1"],
            WorkspaceAgentPresentationOverride(
                state: .waiting,
                phase: .awaitingInput,
                attention: nil,
                summary: "实现完成，等待你验收。"
            )
        )
    }

    func testEvaluatePresentationUsesArtifactActivityToDelayWaitingFallback() {
        let projectPath = "/tmp/project"
        let paneID = "pane-1"
        let candidate = WorkspaceAgentDisplayCandidate(
            projectPath: projectPath,
            paneID: paneID,
            signalSessionID: "session-1",
            signalState: .running,
            signalPhase: .thinking,
            signalUpdatedAt: Date(timeIntervalSinceReferenceDate: 100)
        )
        let visibleSnapshot = CodexAgentDisplaySnapshot(
            recentTextWindow: "/model to change",
            lastActivityAt: Date(timeIntervalSinceReferenceDate: 100)
        )
        let artifact = CodexSessionArtifactSnapshot(
            sessionID: "session-1",
            threadTitle: nil,
            lastActivityAt: Date(timeIntervalSinceReferenceDate: 200.5),
            lastAssistantSummary: nil,
            lastTaskCompleteSummary: nil,
            lastTaskCompleteAt: nil,
            sessionFileURL: nil
        )

        let evaluation = CodexAgentPresentationCoordinator.evaluatePresentation(
            for: [candidate],
            runtimeState: .init(),
            now: Date(timeIntervalSinceReferenceDate: 201),
            artifactProvider: { sessionID in
                sessionID == "session-1" ? artifact : nil
            },
            snapshotProvider: { candidateProjectPath, candidatePaneID in
                guard candidateProjectPath == projectPath, candidatePaneID == paneID else {
                    return nil
                }
                return visibleSnapshot
            }
        )

        XCTAssertTrue(evaluation.overridesByProjectPath.isEmpty)
        XCTAssertEqual(
            evaluation.nextRefreshDeadline,
            Date(timeIntervalSinceReferenceDate: 202.5)
        )
    }

    func testEvaluatePresentationAllowsPostSignalArtifactActivityToOverrideWaitingInput() {
        let projectPath = "/tmp/project"
        let paneID = "pane-1"
        let signalTime = Date(timeIntervalSinceReferenceDate: 100)
        let candidate = WorkspaceAgentDisplayCandidate(
            projectPath: projectPath,
            paneID: paneID,
            signalSessionID: "session-1",
            signalState: .waiting,
            signalPhase: .awaitingInput,
            signalAttention: .input,
            signalUpdatedAt: signalTime
        )
        let visibleSnapshot = CodexAgentDisplaySnapshot(
            recentTextWindow: "Called siyuan.siyuan_update_block",
            lastActivityAt: signalTime
        )
        let artifact = CodexSessionArtifactSnapshot(
            sessionID: "session-1",
            threadTitle: nil,
            lastActivityAt: signalTime.addingTimeInterval(3),
            lastAssistantSummary: "继续处理中",
            lastTaskCompleteSummary: nil,
            lastTaskCompleteAt: nil,
            sessionFileURL: nil
        )

        let evaluation = CodexAgentPresentationCoordinator.evaluatePresentation(
            for: [candidate],
            runtimeState: .init(),
            now: signalTime.addingTimeInterval(4),
            artifactProvider: { sessionID in
                sessionID == "session-1" ? artifact : nil
            },
            snapshotProvider: { candidateProjectPath, candidatePaneID in
                guard candidateProjectPath == projectPath, candidatePaneID == paneID else {
                    return nil
                }
                return visibleSnapshot
            }
        )

        XCTAssertEqual(
            evaluation.overridesByProjectPath[projectPath]?[paneID],
            WorkspaceAgentPresentationOverride(
                state: .running,
                phase: .thinking,
                attention: WorkspaceAgentAttentionRequirement.none,
                summary: "继续处理中"
            )
        )
        XCTAssertEqual(
            evaluation.nextRefreshDeadline,
            signalTime.addingTimeInterval(5)
        )
    }
}
