import XCTest
import Observation
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

    func testUpdateTitleDoesNotInvalidateObservationWhenResolvedTitleMatchesCurrentTitle() {
        let controller = GhosttyWorkspaceController(projectPath: "/tmp/project")
        let createdTab = controller.createTab()

        let invalidationExpectation = expectation(description: "observation invalidation")
        invalidationExpectation.isInverted = true
        withObservationTracking {
            _ = controller.tabs.first(where: { $0.id == createdTab.id })?.title
        } onChange: {
            invalidationExpectation.fulfill()
        }

        controller.updateTitle(for: createdTab.id, title: "Codex Running (12s)")

        wait(for: [invalidationExpectation], timeout: 0.1)
    }

    func testUpdatePaneItemTitleDoesNotEmitChangeWhenTrimmedTitleMatchesCurrentTitle() {
        let controller = GhosttyWorkspaceController(projectPath: "/tmp/project")
        let createdTab = controller.createTab()
        guard let pane = createdTab.leaves.first,
              let item = pane.selectedItem else {
            XCTFail("默认工作区应创建选中 pane item")
            return
        }

        var changeCount = 0
        controller.onChange = {
            changeCount += 1
        }

        controller.updatePaneItemTitle(
            inPane: pane.id,
            itemID: item.id,
            title: "  \(item.title)  "
        )

        let updatedTitle = controller.tabs
            .first(where: { $0.id == createdTab.id })?
            .leaves
            .first(where: { $0.id == pane.id })?
            .items
            .first(where: { $0.id == item.id })?
            .title
        XCTAssertEqual(
            updatedTitle,
            item.title
        )
        XCTAssertEqual(
            changeCount,
            0,
            "当 pane item 标题裁剪后与当前值一致时，不应触发 workspace controller 变更广播。"
        )
    }

    func testUpdatePaneItemTitleDoesNotInvalidateObservationWhenTrimmedTitleMatchesCurrentTitle() {
        let controller = GhosttyWorkspaceController(projectPath: "/tmp/project")
        let createdTab = controller.createTab()
        guard let pane = createdTab.leaves.first,
              let item = pane.selectedItem else {
            XCTFail("默认工作区应创建选中 pane item")
            return
        }

        let invalidationExpectation = expectation(description: "pane item title observation invalidation")
        invalidationExpectation.isInverted = true
        withObservationTracking {
            _ = controller.tabs
                .first(where: { $0.id == createdTab.id })?
                .leaves
                .first(where: { $0.id == pane.id })?
                .items
                .first(where: { $0.id == item.id })?
                .title
        } onChange: {
            invalidationExpectation.fulfill()
        }

        controller.updatePaneItemTitle(
            inPane: pane.id,
            itemID: item.id,
            title: "  \(item.title)  "
        )

        wait(for: [invalidationExpectation], timeout: 0.1)
    }

    func testCreateTabSeedsPaneItemTitleFromWorkingDirectoryDisplayPath() {
        let projectPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("WebstormProjects/DevHaven")
            .path
        let controller = GhosttyWorkspaceController(projectPath: projectPath)
        let createdTab = controller.createTab()
        guard let pane = createdTab.leaves.first,
              let item = pane.selectedItem else {
            XCTFail("默认工作区应创建选中 pane item")
            return
        }

        XCTAssertEqual(
            item.title,
            "~/WebstormProjects/DevHaven",
            "terminal pane item 初始标题应直接展示规范化后的 cwd 路径。"
        )
    }

    func testUpdatePaneItemTitleNormalizesAbsoluteHomePath() {
        let controller = GhosttyWorkspaceController(projectPath: "/tmp/project")
        let createdTab = controller.createTab()
        guard let pane = createdTab.leaves.first,
              let item = pane.selectedItem else {
            XCTFail("默认工作区应创建选中 pane item")
            return
        }
        let absoluteHomePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("WebstormProjects/DevHaven")
            .path

        var changeCount = 0
        controller.onChange = {
            changeCount += 1
        }

        controller.updatePaneItemTitle(
            inPane: pane.id,
            itemID: item.id,
            title: absoluteHomePath
        )

        let updatedTitle = controller.tabs
            .first(where: { $0.id == createdTab.id })?
            .leaves
            .first(where: { $0.id == pane.id })?
            .items
            .first(where: { $0.id == item.id })?
            .title
        XCTAssertEqual(
            updatedTitle,
            "~/WebstormProjects/DevHaven",
            "terminal pane item 标题应展示 home 缩写路径，而不是完整 /Users 路径。"
        )
        XCTAssertEqual(
            changeCount,
            1,
            "当 cwd 的显示路径真实变化时，应只触发一次 workspace controller 变更广播。"
        )
    }

    func testUpdatePaneItemTitleDoesNotInvalidateObservationWhenNormalizedPathMatchesCurrentTitle() {
        let projectPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("WebstormProjects/DevHaven")
            .path
        let controller = GhosttyWorkspaceController(projectPath: projectPath)
        let createdTab = controller.createTab()
        guard let pane = createdTab.leaves.first,
              let item = pane.selectedItem else {
            XCTFail("默认工作区应创建选中 pane item")
            return
        }

        let invalidationExpectation = expectation(description: "pane item normalized path observation invalidation")
        invalidationExpectation.isInverted = true
        withObservationTracking {
            _ = controller.tabs
                .first(where: { $0.id == createdTab.id })?
                .leaves
                .first(where: { $0.id == pane.id })?
                .items
                .first(where: { $0.id == item.id })?
                .title
        } onChange: {
            invalidationExpectation.fulfill()
        }

        controller.updatePaneItemTitle(
            inPane: pane.id,
            itemID: item.id,
            title: projectPath
        )

        wait(for: [invalidationExpectation], timeout: 0.1)
    }

    func testUpdatePaneItemTitlePreservesNonPathRuntimeTitle() {
        let projectPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("WebstormProjects/DevHaven")
            .path
        let controller = GhosttyWorkspaceController(projectPath: projectPath)
        let createdTab = controller.createTab()
        guard let pane = createdTab.leaves.first,
              let item = pane.selectedItem else {
            XCTFail("默认工作区应创建选中 pane item")
            return
        }

        var changeCount = 0
        controller.onChange = {
            changeCount += 1
        }

        controller.updatePaneItemTitle(
            inPane: pane.id,
            itemID: item.id,
            title: "git status"
        )

        let updatedTitle = controller.tabs
            .first(where: { $0.id == createdTab.id })?
            .leaves
            .first(where: { $0.id == pane.id })?
            .items
            .first(where: { $0.id == item.id })?
            .title
        XCTAssertEqual(
            updatedTitle,
            "git status",
            "非路径 runtime title 应沿用改动前行为继续显示，只对路径做规范化。"
        )
        XCTAssertEqual(
            changeCount,
            1,
            "非路径 runtime title 到达时，应触发一次 pane title 更新。"
        )
    }

    func testUpdatePaneItemTitlePreservesCodexRuntimeStatusTitle() {
        let projectPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("WebstormProjects/DevHaven")
            .path
        let controller = GhosttyWorkspaceController(projectPath: projectPath)
        let createdTab = controller.createTab()
        guard let pane = createdTab.leaves.first,
              let item = pane.selectedItem else {
            XCTFail("默认工作区应创建选中 pane item")
            return
        }

        var changeCount = 0
        controller.onChange = {
            changeCount += 1
        }

        controller.updatePaneItemTitle(
            inPane: pane.id,
            itemID: item.id,
            title: "Working (12s) esc to interrupt"
        )

        let updatedTitle = controller.tabs
            .first(where: { $0.id == createdTab.id })?
            .leaves
            .first(where: { $0.id == pane.id })?
            .items
            .first(where: { $0.id == item.id })?
            .title
        XCTAssertEqual(
            updatedTitle,
            "Working (12s) esc to interrupt",
            "Codex TUI 的运行状态标题应继续显示在 pane title 上。"
        )
        XCTAssertEqual(
            changeCount,
            1,
            "Codex TUI 运行状态标题到达时，应触发一次 pane title 更新。"
        )
    }

    func testPaneTitlePolicyMatchesWorkingDirectoryDisplayForEquivalentHomePaths() {
        let workingDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("WebstormProjects/DevHaven")
            .path

        XCTAssertTrue(
            WorkspaceTerminalPaneTitlePolicy.matchesWorkingDirectoryDisplay(
                title: workingDirectory,
                workingDirectory: "~/WebstormProjects/DevHaven"
            ),
            "绝对 home 路径与 ~ 缩写路径应视为同一 cwd 展示，供 App 层忽略冗余 title 回声。"
        )
    }

    func testUpdatePaneItemTitleIgnoresPromptDecoratedHostPathEcho() {
        let projectPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("WebstormProjects/DevHaven")
            .path
        let controller = GhosttyWorkspaceController(projectPath: projectPath)
        let createdTab = controller.createTab()
        guard let pane = createdTab.leaves.first,
              let item = pane.selectedItem else {
            XCTFail("默认工作区应创建选中 pane item")
            return
        }

        var changeCount = 0
        controller.onChange = {
            changeCount += 1
        }

        controller.updatePaneItemTitle(
            inPane: pane.id,
            itemID: item.id,
            title: "zhaotianzeng@Mac-mini  ~/WebstormProjects/DevHaven"
        )

        let updatedTitle = controller.tabs
            .first(where: { $0.id == createdTab.id })?
            .leaves
            .first(where: { $0.id == pane.id })?
            .items
            .first(where: { $0.id == item.id })?
            .title
        XCTAssertEqual(
            updatedTitle,
            item.title,
            "带主机名与 prompt 装饰的路径回声应收口回 cwd 路径展示，不应把主机名显示到 pane title。"
        )
        XCTAssertEqual(
            changeCount,
            0,
            "prompt 风格路径回声不应触发 pane title 变更广播。"
        )
    }

    func testUpdatePaneItemTitleIgnoresColonSeparatedHostPathEcho() {
        let projectPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("WebstormProjects/DevHaven")
            .path
        let controller = GhosttyWorkspaceController(projectPath: projectPath)
        let createdTab = controller.createTab()
        guard let pane = createdTab.leaves.first,
              let item = pane.selectedItem else {
            XCTFail("默认工作区应创建选中 pane item")
            return
        }

        var changeCount = 0
        controller.onChange = {
            changeCount += 1
        }

        controller.updatePaneItemTitle(
            inPane: pane.id,
            itemID: item.id,
            title: "zhaotianzeng@Mac-mini:~/WebstormProjects/DevHaven"
        )

        let updatedTitle = controller.tabs
            .first(where: { $0.id == createdTab.id })?
            .leaves
            .first(where: { $0.id == pane.id })?
            .items
            .first(where: { $0.id == item.id })?
            .title
        XCTAssertEqual(
            updatedTitle,
            item.title,
            "user@host:~/path 形式也应收口回 cwd 路径展示，不应把主机名显示到 pane title。"
        )
        XCTAssertEqual(
            changeCount,
            0,
            "无空格 host:path 回声不应触发 pane title 变更广播。"
        )
    }
}
