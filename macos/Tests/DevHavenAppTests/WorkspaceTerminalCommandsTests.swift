import XCTest

final class WorkspaceTerminalCommandsTests: XCTestCase {
    func testWorkspaceShellPublishesFocusedSearchActionsForActiveTerminalPane() throws {
        let source = try String(contentsOf: workspaceShellFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains(".focusedSceneValue(\\.startTerminalSearchAction"),
            "WorkspaceShellView 应向当前 scene 暴露“开始搜索”动作，供 App 菜单路由到当前 terminal pane"
        )
        XCTAssertTrue(
            source.contains(".focusedSceneValue(\\.searchSelectionAction"),
            "WorkspaceShellView 应暴露“使用所选内容查找”动作，供 App 菜单路由到当前 terminal pane"
        )
        XCTAssertTrue(
            source.contains(".focusedSceneValue(\\.navigateTerminalSearchNextAction"),
            "WorkspaceShellView 应暴露“查找下一个”动作，供 App 菜单路由到当前 terminal pane"
        )
        XCTAssertTrue(
            source.contains(".focusedSceneValue(\\.navigateTerminalSearchPreviousAction"),
            "WorkspaceShellView 应暴露“查找上一个”动作，供 App 菜单路由到当前 terminal pane"
        )
        XCTAssertTrue(
            source.contains(".focusedSceneValue(\\.endTerminalSearchAction"),
            "WorkspaceShellView 应暴露“隐藏查找栏”动作，供 App 菜单路由到当前 terminal pane"
        )
    }

    func testWorkspaceDefinesFocusedValueKeysForTerminalSearchCommands() throws {
        let source = try String(contentsOf: commandsFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("struct WorkspaceTerminalCommands: Commands"),
            "应用应新增独立的 WorkspaceTerminalCommands，用于收口 terminal 搜索菜单"
        )
        XCTAssertTrue(
            source.contains("@FocusedValue(\\.startTerminalSearchAction)"),
            "WorkspaceTerminalCommands 应读取 scene 提供的开始搜索动作"
        )
        XCTAssertTrue(
            source.contains("var startTerminalSearchAction"),
            "应定义 startTerminalSearchAction 的 FocusedValue 接口"
        )
        XCTAssertTrue(
            source.contains("var navigateTerminalSearchNextAction"),
            "应定义 navigateTerminalSearchNextAction 的 FocusedValue 接口"
        )
        XCTAssertTrue(
            source.contains("var navigateTerminalSearchPreviousAction"),
            "应定义 navigateTerminalSearchPreviousAction 的 FocusedValue 接口"
        )
        XCTAssertTrue(
            source.contains("var endTerminalSearchAction"),
            "应定义 endTerminalSearchAction 的 FocusedValue 接口"
        )
        XCTAssertTrue(
            source.contains("查找…"),
            "WorkspaceTerminalCommands 应提供“查找…”菜单项"
        )
        XCTAssertTrue(
            source.contains("查找下一个"),
            "WorkspaceTerminalCommands 应提供“查找下一个”菜单项"
        )
        XCTAssertTrue(
            source.contains("查找上一个"),
            "WorkspaceTerminalCommands 应提供“查找上一个”菜单项"
        )
        XCTAssertTrue(
            source.contains("隐藏查找栏"),
            "WorkspaceTerminalCommands 应提供“隐藏查找栏”菜单项"
        )
        XCTAssertTrue(
            source.contains("使用所选内容查找"),
            "WorkspaceTerminalCommands 应提供“使用所选内容查找”菜单项"
        )
    }

    private func workspaceShellFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/WorkspaceShellView.swift")
    }

    private func commandsFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/WorkspaceTerminalCommands.swift")
    }
}
