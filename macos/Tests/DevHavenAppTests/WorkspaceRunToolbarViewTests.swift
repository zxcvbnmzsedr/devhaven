import XCTest

final class WorkspaceRunToolbarViewTests: XCTestCase {
    func testRunToolbarExposesConfigurationMenuAndRunStopLogsConfigureButtons() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("Menu {"), "运行工具栏应提供运行配置菜单")
        XCTAssertFalse(source.contains("通用脚本"), "运行菜单不应把通用脚本直接当成可运行配置")
        XCTAssertTrue(source.contains("Button(\"Run\")"), "运行工具栏应提供显式 Run 按钮")
        XCTAssertTrue(source.contains("Button(\"Stop\")"), "运行工具栏应提供显式 Stop 按钮")
        XCTAssertTrue(source.contains("Button(\"Logs\")"), "运行工具栏应提供 Logs 展开/收起入口")
        XCTAssertTrue(source.contains("Button(\"配置\")"), "运行工具栏应提供直达运行配置入口")
    }

    private func sourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/WorkspaceRunToolbarView.swift")
    }
}
