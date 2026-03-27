import XCTest

final class WorkspaceDiffPaneHeaderViewTests: XCTestCase {
    func testPaneHeaderRendersMetadataInsteadOfAdHocSubtitle() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("metadata.title"), "pane header 应渲染结构化 metadata.title")
        XCTAssertTrue(source.contains("metadata.path"), "pane header 应渲染结构化 metadata.path")
        XCTAssertTrue(source.contains("metadata.oldPath"), "pane header 应显式展示 rename oldPath")
        XCTAssertTrue(source.contains("metadata.primaryDetails"), "pane header 应消费 revision/hash 主信息")
        XCTAssertTrue(source.contains("metadata.secondaryDetails"), "pane header 应消费 author/time 次信息")
    }

    private func sourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/WorkspaceDiffPaneHeaderView.swift")
    }
}
