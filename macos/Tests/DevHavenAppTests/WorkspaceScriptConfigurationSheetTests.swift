import XCTest

final class WorkspaceScriptConfigurationSheetTests: XCTestCase {
    func testConfigurationSheetUsesTypedRunConfigurations() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("struct WorkspaceRunConfigurationSheet"), "配置面板应升级为 typed 运行配置编辑器命名")
        XCTAssertTrue(source.contains("case customShell"), "配置类型至少应支持 customShell")
        XCTAssertTrue(source.contains("case remoteLogViewer"), "配置类型至少应支持 remoteLogViewer")
        XCTAssertTrue(source.contains("复制当前配置"), "面板应提供复制配置入口，降低重复录入成本")
        XCTAssertTrue(source.contains("命令预览"), "typed 配置面板应展示只读命令预览，降低用户理解成本")
        XCTAssertTrue(source.contains("连接设置"), "remoteLogViewer 应按连接设置分组展示")
        XCTAssertTrue(source.contains("日志设置"), "remoteLogViewer 应按日志设置分组展示")
        XCTAssertTrue(source.contains("安全设置"), "remoteLogViewer 应按安全设置分组展示")
        XCTAssertTrue(source.contains("suggestedName"), "面板应具备建议名称逻辑，尽量减少手动命名成本")
        XCTAssertTrue(source.contains("viewModel.saveWorkspaceRunConfigurations"), "配置面板保存时应回写当前项目的 typed 运行配置")
        XCTAssertFalse(source.contains("插入通用脚本（可选）"), "typed 配置面板不应再暴露通用脚本模板入口")
        XCTAssertFalse(source.contains("onManageSharedScripts"), "typed 配置面板不应再耦合 shared scripts 管理回调")
        XCTAssertFalse(source.contains("运行配置类型"), "类型应在创建时确定，而不是在编辑页里通过 picker 来回切换")
    }

    private func sourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/WorkspaceScriptConfigurationSheet.swift")
    }
}
