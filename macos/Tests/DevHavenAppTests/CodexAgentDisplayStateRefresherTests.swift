import XCTest
@testable import DevHavenApp
@testable import DevHavenCore

@MainActor
final class CodexAgentDisplayStateRefresherTests: XCTestCase {
    func testWaitingSignalPromotesBackToRunningWhenSnapshotTextChangesAwayFromIdleScreen() {
        let candidate = WorkspaceAgentDisplayCandidate(
            projectPath: "/tmp/devhaven",
            paneID: "pane-1",
            signalState: .waiting
        )
        var runtimeState = CodexAgentDisplayStateRefresher.RuntimeState()
        let initialWaitingScreen = """
        OpenAI Codex (v0.116.0)
        model:    gpt-5.4 xhigh   /model to change
        directory: ~/DevHaven
        """

        _ = CodexAgentDisplayStateRefresher.presentationOverrides(
            for: [candidate],
            runtimeState: &runtimeState,
            now: Date(timeIntervalSince1970: 100)
        ) { _, _ in
            makeSnapshot(
                text: initialWaitingScreen,
                lastActivityAt: Date(timeIntervalSince1970: 100)
            )
        }

        let changedOutput = """
        OpenAI Codex (v0.116.0)
        正在分析最近的输出片段
        """
        let overrides = CodexAgentDisplayStateRefresher.presentationOverrides(
            for: [candidate],
            runtimeState: &runtimeState,
            now: Date(timeIntervalSince1970: 101)
        ) { _, _ in
            makeSnapshot(
                text: changedOutput,
                lastActivityAt: Date(timeIntervalSince1970: 101)
            )
        }

        XCTAssertEqual(overrides["/tmp/devhaven"]?["pane-1"]?.state, .running)
    }

    func testRunningSignalDoesNotFallbackToWaitingWhileVisibleTextIsStillChanging() {
        let candidate = WorkspaceAgentDisplayCandidate(
            projectPath: "/tmp/devhaven",
            paneID: "pane-1",
            signalState: .running
        )
        var runtimeState = CodexAgentDisplayStateRefresher.RuntimeState()
        let previousOutput = """
        OpenAI Codex (v0.116.0)
        Working (13s • esc to interrupt)
        """

        _ = CodexAgentDisplayStateRefresher.presentationOverrides(
            for: [candidate],
            runtimeState: &runtimeState,
            now: Date(timeIntervalSince1970: 200)
        ) { _, _ in
            makeSnapshot(
                text: previousOutput,
                lastActivityAt: Date(timeIntervalSince1970: 200)
            )
        }

        let waitingScreen = """
        OpenAI Codex (v0.116.0)
        model:    gpt-5.4 xhigh   /model to change
        directory: ~/DevHaven
        """
        let overrides = CodexAgentDisplayStateRefresher.presentationOverrides(
            for: [candidate],
            runtimeState: &runtimeState,
            now: Date(timeIntervalSince1970: 201)
        ) { _, _ in
            makeSnapshot(
                text: waitingScreen,
                lastActivityAt: Date(timeIntervalSince1970: 201)
            )
        }

        XCTAssertNil(overrides["/tmp/devhaven"]?["pane-1"])
    }

    func testRunningSignalFallsBackToWaitingAfterIdleScreenStaysStable() {
        let candidate = WorkspaceAgentDisplayCandidate(
            projectPath: "/tmp/devhaven",
            paneID: "pane-1",
            signalState: .running
        )
        var runtimeState = CodexAgentDisplayStateRefresher.RuntimeState()
        let waitingScreen = """
        OpenAI Codex (v0.116.0)
        model:    gpt-5.4 xhigh   /model to change
        directory: ~/DevHaven
        """

        _ = CodexAgentDisplayStateRefresher.presentationOverrides(
            for: [candidate],
            runtimeState: &runtimeState,
            now: Date(timeIntervalSince1970: 300)
        ) { _, _ in
            makeSnapshot(
                text: waitingScreen,
                lastActivityAt: Date(timeIntervalSince1970: 300)
            )
        }

        let overrides = CodexAgentDisplayStateRefresher.presentationOverrides(
            for: [candidate],
            runtimeState: &runtimeState,
            now: Date(timeIntervalSince1970: 305)
        ) { _, _ in
            makeSnapshot(
                text: waitingScreen,
                lastActivityAt: Date(timeIntervalSince1970: 300)
            )
        }

        XCTAssertEqual(overrides["/tmp/devhaven"]?["pane-1"]?.state, .waiting)
    }

    func testIgnoresCandidateWhenSnapshotProviderReturnsNil() {
        let candidate = WorkspaceAgentDisplayCandidate(
            projectPath: "/tmp/devhaven",
            paneID: "pane-1",
            signalState: .running
        )
        var runtimeState = CodexAgentDisplayStateRefresher.RuntimeState()

        let overrides = CodexAgentDisplayStateRefresher.presentationOverrides(
            for: [candidate],
            runtimeState: &runtimeState,
            now: Date(timeIntervalSince1970: 400)
        ) { _, _ in
            nil
        }

        XCTAssertTrue(overrides.isEmpty)
    }

    private func makeSnapshot(
        text: String,
        lastActivityAt: Date
    ) -> CodexAgentDisplaySnapshot {
        CodexAgentDisplaySnapshot(
            recentTextWindow: text,
            lastActivityAt: lastActivityAt
        )
    }
}
