import XCTest

final class DevHavenAppCommandTests: XCTestCase {
    func testCommandsReplaceDefaultNewItemGroupToDisableCommandN() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("CommandGroup(replacing: .newItem)"),
            "应用应显式覆盖默认 newItem 命令组，避免 macOS 默认“新建窗口”继续响应 ⌘N"
        )
    }

    func testCommandsExposeCheckForUpdatesAction() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("检查更新"),
            "应用菜单应提供手动“检查更新”入口，方便用户主动触发 Sparkle 检查"
        )
    }

    func testCommandsExposeGhosttySearchActions() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("WorkspaceTerminalCommands()"),
            "DevHavenApp 应挂接独立的 WorkspaceTerminalCommands，把 terminal 搜索命令接入应用级菜单"
        )
    }

    func testCommandsExposeWorkspaceOpenProjectAction() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("WorkspaceProjectCommands("),
            "DevHavenApp 应挂接独立的 WorkspaceProjectCommands，把 workspace 打开项目命令接入应用级菜单"
        )
        XCTAssertTrue(
            source.contains("workspaceOpenProjectShortcut"),
            "打开项目菜单快捷键应来自设置里的 workspaceOpenProjectShortcut，而不是写死在命令层"
        )
    }

    private func sourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/DevHavenApp.swift")
    }
}
