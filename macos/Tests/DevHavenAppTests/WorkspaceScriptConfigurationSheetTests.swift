import XCTest

final class WorkspaceScriptConfigurationSheetTests: XCTestCase {
    func testConfigurationSheetUsesSharedScriptsAsProjectScriptTemplates() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("插入通用脚本（可选）"), "脚本配置面板应提供 archive/2.8.3 同款的通用脚本插入入口")
        XCTAssertTrue(source.contains("ScriptTemplateSupport.applySharedScriptTemplate"), "选择通用脚本时应把模板展开成项目脚本命令")
        XCTAssertTrue(source.contains("viewModel.saveWorkspaceScripts"), "脚本配置面板保存时应回写当前项目的 Project.scripts")
    }

    private func sourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/WorkspaceScriptConfigurationSheet.swift")
    }
}
