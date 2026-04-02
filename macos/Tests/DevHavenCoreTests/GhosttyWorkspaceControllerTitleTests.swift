import XCTest
@testable import DevHavenCore

@MainActor
final class GhosttyWorkspaceControllerTitleTests: XCTestCase {
    func testUpdateTitleDoesNotEmitChangeWhenResolvedTitleMatchesCurrentTitle() {
        let controller = GhosttyWorkspaceController(projectPath: "/tmp/project")
        let createdTab = controller.createTab()
        let originalTitle = createdTab.title

        var changeCount = 0
        controller.onChange = {
            changeCount += 1
        }

        controller.updateTitle(for: createdTab.id, title: "Codex Running (12s)")

        XCTAssertEqual(
            controller.tabs.first(where: { $0.id == createdTab.id })?.title,
            originalTitle
        )
        XCTAssertEqual(
            changeCount,
            0,
            "当运行时标题解析结果与当前标题一致时，不应触发 workspace controller 变更广播。"
        )
    }
}
