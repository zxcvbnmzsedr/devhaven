import XCTest
@testable import DevHavenCore

final class ScriptTemplateSupportTests: XCTestCase {
    func testSharedScriptTemplateFeedsProjectScriptConfiguration() {
        let command = ScriptTemplateSupport.applySharedScriptTemplate(
            commandTemplate: "bash \"${scriptPath}\" --lines \"${lines}\" --token \"${TOKEN}\"",
            absolutePath: "/tmp/shared-log.sh"
        )
        let schema = ScriptTemplateSupport.mergeParamSchema(
            command: command,
            schema: [
                ScriptParamField(key: "lines", label: "输出行数", type: .number, required: true, defaultValue: "200", description: "默认读取最近 200 行")
            ]
        )
        let templateParams = ScriptTemplateSupport.buildTemplateParams(schema: schema, explicitValues: [:])
        let resolution = ScriptTemplateSupport.resolveCommand(template: command, paramSchema: schema, explicitValues: templateParams)

        XCTAssertEqual(schema.map(\.key), ["lines"], "scriptPath 与全大写环境变量不应被当成项目脚本参数")
        XCTAssertEqual(templateParams, ["lines": "200"])
        XCTAssertTrue(resolution.missingRequiredKeys.isEmpty)
        XCTAssertTrue(resolution.command.contains("lines='200'"))
        XCTAssertTrue(resolution.command.contains("bash \"/tmp/shared-log.sh\" --lines \"${lines}\""))
    }

    func testResolveCommandReportsMissingRequiredKeys() {
        let resolution = ScriptTemplateSupport.resolveCommand(
            template: "bash run.sh --token \"${token}\"",
            paramSchema: [
                ScriptParamField(key: "token", label: "访问令牌", type: .secret, required: true, defaultValue: nil, description: nil)
            ],
            explicitValues: [:]
        )

        XCTAssertEqual(resolution.missingRequiredKeys, ["访问令牌"])
    }
}
