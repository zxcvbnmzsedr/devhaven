import XCTest

final class SettingsViewTests: XCTestCase {
    func testTerminalSettingsExposeGhosttyConfigEntryInsteadOfLegacyTauriToggles() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("编辑 Ghostty 配置文件"),
            "终端设置应直接提供 Ghostty 配置文件入口，方便用户进入真实配置源"
        )
        XCTAssertTrue(
            source.contains("打开配置目录"),
            "终端设置应提供打开配置目录入口，方便用户查看关联资源"
        )
        XCTAssertFalse(
            source.contains("启用 WebGL 渲染"),
            "原生 Ghostty 设置页不应继续暴露仅属于旧 Tauri 终端的 WebGL 开关"
        )
        XCTAssertFalse(
            source.contains("跟随系统浅 / 深色"),
            "终端主题应交由 Ghostty 配置文件管理，而不是继续保留旧的应用内主题开关"
        )
    }

    func testNextSettingsPreservesWorkspaceSidebarWidth() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("workspaceSidebarWidth: originalSettings.workspaceSidebarWidth"),
            "设置页保存其他配置时也应保留现有的工作区侧边栏宽度，不能把该值意外重置"
        )
    }

    func testGeneralSettingsExposeUpdateControls() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("升级通道"), "设置页应暴露升级通道，允许 stable/nightly 切换")
        XCTAssertTrue(source.contains("自动检查更新"), "设置页应允许用户配置自动检查更新")
        XCTAssertTrue(source.contains("自动下载更新"), "设置页应允许用户配置自动下载更新")
        XCTAssertTrue(source.contains("立即检查更新"), "设置页应提供手动检查更新入口")
        XCTAssertTrue(source.contains("打开下载页"), "无苹果开发者账号模式下，设置页应提供打开下载页入口")
    }

    func testWorkspaceSettingsExposeNotificationControls() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("应用内工作区通知"), "设置页应允许用户开关应用内工作区通知")
        XCTAssertTrue(source.contains("系统通知"), "设置页应允许用户开关 macOS 系统通知")
        XCTAssertTrue(source.contains("收到通知时将 worktree 置顶"), "设置页应允许用户控制通知后 worktree 置顶行为")
    }

    func testGeneralSettingsExposeWorkspaceOpenProjectShortcutControls() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("打开项目快捷键"), "设置页常规项应暴露 workspace 打开项目快捷键配置入口")
        XCTAssertTrue(source.contains("workspaceOpenProjectShortcut"), "设置页应维护打开项目快捷键的本地编辑状态")
        XCTAssertTrue(source.contains("workspaceOpenProjectShortcut: workspaceOpenProjectShortcut"), "设置页保存时应写回打开项目快捷键配置")
    }

    private func sourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/SettingsView.swift")
    }
}
