import XCTest

final class ProjectDetailRootViewTests: XCTestCase {
    func testMarkdownSectionDoesNotRenderFullReadmeInline() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertFalse(
            source.contains("Text(readme.content)"),
            "详情面板不应直接把整份 README 原文一次性塞进 Text；README 很长时会让右侧面板打开/关闭都变慢，用户体感就是转圈"
        )
        XCTAssertTrue(
            source.contains("ProjectDetailMarkdownPresentationPolicy"),
            "README 展示应先经过轻量预览策略，而不是直接内联渲染原文"
        )
    }

    private func sourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/ProjectDetailRootView.swift")
    }
}
