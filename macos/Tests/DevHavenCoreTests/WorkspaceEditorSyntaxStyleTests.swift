import XCTest
@testable import DevHavenCore

final class WorkspaceEditorSyntaxStyleTests: XCTestCase {
    func testInferSyntaxStyleFromFilePath() {
        XCTAssertEqual(WorkspaceEditorSyntaxStyle.infer(fromFilePath: "/tmp/App.swift"), .swift)
        XCTAssertEqual(WorkspaceEditorSyntaxStyle.infer(fromFilePath: "/tmp/data.json"), .json)
        XCTAssertEqual(WorkspaceEditorSyntaxStyle.infer(fromFilePath: "/tmp/README.md"), .markdown)
        XCTAssertEqual(WorkspaceEditorSyntaxStyle.infer(fromFilePath: "/tmp/config.yaml"), .yaml)
        XCTAssertEqual(WorkspaceEditorSyntaxStyle.infer(fromFilePath: "/tmp/plain.txt"), .plainText)
    }
}
