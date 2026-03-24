import XCTest
@testable import DevHavenCore

final class ScriptTemplateSupportTests: XCTestCase {
    func testResolveCommandFlattensLegacyTemplateParamsIntoAssignments() {
        let resolution = ScriptTemplateSupport.resolveCommand(
            template: "server=${server}\nexec printf '%s\\n' \"$server\"",
            paramSchema: [
                ScriptParamField(key: "server", label: "服务器", type: .text, required: true, defaultValue: nil, description: nil)
            ],
            explicitValues: ["server": "root@192.168.0.131"]
        )

        XCTAssertTrue(resolution.missingRequiredKeys.isEmpty)
        XCTAssertEqual(
            resolution.command,
            "server='root@192.168.0.131'\nserver=${server}\nexec printf '%s\\n' \"$server\""
        )
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

    func testNormalizeShellTemplateTextReplacesSmartQuotes() {
        let normalized = ScriptTemplateSupport.normalizeShellTemplateText("echo \u{2018}hello\u{2019} \u{201C}world\u{201D}")
        XCTAssertEqual(normalized, "echo 'hello' \"world\"")
    }
}
