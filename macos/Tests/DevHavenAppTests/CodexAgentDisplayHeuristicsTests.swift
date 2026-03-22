import XCTest
@testable import DevHavenApp
@testable import DevHavenCore

final class CodexAgentDisplayHeuristicsTests: XCTestCase {
    func testWorkingMarkerResolvesToRunning() {
        let text = """
        OpenAI Codex (v0.116.0)
        Working (13s • esc to interrupt)
        """

        XCTAssertEqual(CodexAgentDisplayHeuristics.displayState(for: text), .running)
    }

    func testInputPlaceholderWithoutWorkingMarkerResolvesToWaiting() {
        let text = """
        OpenAI Codex (v0.116.0)
        你好。
        Improve documentation in @filename
        """

        XCTAssertEqual(CodexAgentDisplayHeuristics.displayState(for: text), .waiting)
    }

    func testIdleCodexScreenWithoutFixedPlaceholderStillResolvesToWaiting() {
        let text = """
        OpenAI Codex (v0.116.0)
        model:    gpt-5.4 xhigh   /model to change
        directory: ~/WebstormProjects/DevHaven

        你好。
        Explored
          Read SKILL.md

        我在这里，可以帮你：
        - 看代码 / 改 Bug
        - 分析架构
        - 写实现方案
        """

        XCTAssertEqual(CodexAgentDisplayHeuristics.displayState(for: text), .waiting)
    }

    func testEscToInterruptMarkerResolvesToRunning() {
        let text = """
        OpenAI Codex (v0.116.0)
        Starting MCP servers (6/7): serena (1s • esc to interrupt)
        """

        XCTAssertEqual(CodexAgentDisplayHeuristics.displayState(for: text), .running)
    }

    func testUnknownTextKeepsOriginalSignalState() {
        let text = """
        OpenAI Codex (v0.116.0)
        MCP startup incomplete
        """

        XCTAssertNil(CodexAgentDisplayHeuristics.displayState(for: text))
    }
}
