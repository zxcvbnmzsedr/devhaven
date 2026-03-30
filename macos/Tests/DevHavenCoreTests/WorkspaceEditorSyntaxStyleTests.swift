import XCTest
@testable import DevHavenCore

final class WorkspaceEditorSyntaxStyleTests: XCTestCase {
    func testInferSyntaxStyleFromFilePath() {
        XCTAssertEqual(WorkspaceEditorSyntaxStyle.infer(fromFilePath: "/tmp/App.swift"), .swift)
        XCTAssertEqual(WorkspaceEditorSyntaxStyle.infer(fromFilePath: "/tmp/App.m"), .objectiveC)
        XCTAssertEqual(WorkspaceEditorSyntaxStyle.infer(fromFilePath: "/tmp/main.cpp"), .cpp)
        XCTAssertEqual(WorkspaceEditorSyntaxStyle.infer(fromFilePath: "/tmp/App.cs"), .csharp)
        XCTAssertEqual(WorkspaceEditorSyntaxStyle.infer(fromFilePath: "/tmp/data.json"), .json)
        XCTAssertEqual(WorkspaceEditorSyntaxStyle.infer(fromFilePath: "/tmp/README.md"), .markdown)
        XCTAssertEqual(WorkspaceEditorSyntaxStyle.infer(fromFilePath: "/tmp/config.yaml"), .yaml)
        XCTAssertEqual(WorkspaceEditorSyntaxStyle.infer(fromFilePath: "/tmp/script.sh"), .shell)
        XCTAssertEqual(WorkspaceEditorSyntaxStyle.infer(fromFilePath: "/tmp/layout.xml"), .xml)
        XCTAssertEqual(WorkspaceEditorSyntaxStyle.infer(fromFilePath: "/tmp/index.html"), .html)
        XCTAssertEqual(WorkspaceEditorSyntaxStyle.infer(fromFilePath: "/tmp/site.css"), .css)
        XCTAssertEqual(WorkspaceEditorSyntaxStyle.infer(fromFilePath: "/tmp/app.js"), .javascript)
        XCTAssertEqual(WorkspaceEditorSyntaxStyle.infer(fromFilePath: "/tmp/app.ts"), .typescript)
        XCTAssertEqual(WorkspaceEditorSyntaxStyle.infer(fromFilePath: "/tmp/local.properties"), .properties)
        XCTAssertEqual(WorkspaceEditorSyntaxStyle.infer(fromFilePath: "/tmp/App.java"), .java)
        XCTAssertEqual(WorkspaceEditorSyntaxStyle.infer(fromFilePath: "/tmp/App.kt"), .kotlin)
        XCTAssertEqual(WorkspaceEditorSyntaxStyle.infer(fromFilePath: "/tmp/service.py"), .python)
        XCTAssertEqual(WorkspaceEditorSyntaxStyle.infer(fromFilePath: "/tmp/app.rb"), .ruby)
        XCTAssertEqual(WorkspaceEditorSyntaxStyle.infer(fromFilePath: "/tmp/server.go"), .go)
        XCTAssertEqual(WorkspaceEditorSyntaxStyle.infer(fromFilePath: "/tmp/lib.rs"), .rust)
        XCTAssertEqual(WorkspaceEditorSyntaxStyle.infer(fromFilePath: "/tmp/query.sql"), .sql)
        XCTAssertEqual(WorkspaceEditorSyntaxStyle.infer(fromFilePath: "/tmp/plain.txt"), .plainText)
    }
}
