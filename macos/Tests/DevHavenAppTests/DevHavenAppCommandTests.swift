import XCTest

final class DevHavenAppCommandTests: XCTestCase {
    func testCommandsReplaceDefaultNewItemGroupToDisableCommandN() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("CommandGroup(replacing: .newItem)"),
            "应用应显式覆盖默认 newItem 命令组，避免 macOS 默认“新建窗口”继续响应 ⌘N"
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
