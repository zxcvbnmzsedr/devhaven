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

    private func sourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/SettingsView.swift")
    }
}
