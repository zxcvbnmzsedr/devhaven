import XCTest
@testable import DevHavenApp
@testable import DevHavenCore

@MainActor
final class CodexAgentDisplayStateRefresherTests: XCTestCase {
    func testWaitingSignalPromotesBackToRunningWhenVisibleTextChangesAwayFromIdleScreen() {
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
            initialWaitingScreen
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
            changedOutput
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
            previousOutput
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
            waitingScreen
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
            waitingScreen
        }

        let overrides = CodexAgentDisplayStateRefresher.presentationOverrides(
            for: [candidate],
            runtimeState: &runtimeState,
            now: Date(timeIntervalSince1970: 305)
        ) { _, _ in
            waitingScreen
        }

        XCTAssertEqual(overrides["/tmp/devhaven"]?["pane-1"]?.state, .waiting)
    }
}
