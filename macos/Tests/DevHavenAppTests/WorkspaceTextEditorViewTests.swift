import XCTest

final class WorkspaceTextEditorViewTests: XCTestCase {
    func testWorkspaceTextEditorViewBridgesHighlightsAndScrollSync() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("struct WorkspaceTextEditorScrollRequestState"), "文本编辑宿主应定义显式滚动请求状态")
        XCTAssertTrue(source.contains("let highlights: [WorkspaceDiffEditorHighlight]"), "文本编辑宿主必须显式接收 line highlights")
        XCTAssertTrue(source.contains("let inlineHighlights: [WorkspaceDiffEditorInlineHighlight]"), "文本编辑宿主必须显式接收字符级 inline highlights")
        XCTAssertTrue(source.contains("let scrollSyncState: Binding<WorkspaceTextEditorScrollSyncState>?"), "文本编辑宿主必须显式接收滚动同步状态")
        XCTAssertTrue(source.contains("let scrollRequestState: Binding<WorkspaceTextEditorScrollRequestState>?"), "文本编辑宿主必须显式接收滚动请求状态")
        XCTAssertTrue(source.contains("boundsDidChangeNotification"), "同步滚动应监听 scroll view 的 bounds 变化")
        XCTAssertTrue(source.contains("applyHighlights"), "文本编辑宿主应把高亮桥接到 NSTextView")
        XCTAssertTrue(source.contains("applyInlineHighlights"), "文本编辑宿主应把字符级高亮桥接到 NSTextView")
        XCTAssertTrue(source.contains("scrollToRequestedLineIfNeeded"), "文本编辑宿主应在收到请求时滚动到指定行")
    }

    func testWorkspaceTextEditorViewCachesDecorationSignatureBeforeReapplyingHighlights() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("WorkspaceTextEditorDecorationSignature"), "文本编辑宿主应定义 decoration signature，用于跳过无关高亮重刷")
        XCTAssertTrue(source.contains("lastAppliedDecorationSignature"), "Coordinator 应缓存上次应用的 decoration signature")
        XCTAssertTrue(source.contains("applyDecorationsIfNeeded"), "文本编辑宿主应通过独立 helper 决定是否重刷 decorations")
        XCTAssertTrue(source.contains("force || lastAppliedDecorationSignature != signature"), "只有文本变化或 signature 变化时才应重刷全文高亮")
    }

    func testWorkspaceTextEditorViewReceivesSelectedDifferenceDrivenScrollRequests() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("enum WorkspaceTextEditorScrollRequestKind"), "文本编辑宿主应把滚动请求语义结构化，而不是只传 revision")
        XCTAssertTrue(source.contains("var kind: WorkspaceTextEditorScrollRequestKind"), "滚动请求状态应显式携带请求语义")
        XCTAssertTrue(source.contains(".manual"), "滚动请求默认语义应保持为 manual，避免破坏旧调用")
    }

    func testWorkspaceTextEditorViewShortCircuitsRemoteScrollEchoAndNoOpSyncWrites() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("remoteScrollTolerance"), "文本编辑宿主应为程序化同步滚动提供位置容差，避免滚动回环")
        XCTAssertTrue(source.contains("localScrollEmissionThreshold"), "文本编辑宿主应限制本地滚动状态写频率，避免每个像素都打脏 SwiftUI")
        XCTAssertTrue(source.contains("lastProgrammaticScrollOriginY"), "文本编辑宿主应记录最近一次程序化滚动目标位置，用于吞掉 boundsDidChange 回声")
        XCTAssertTrue(source.contains("abs(clipView.bounds.origin.y - targetY) < Self.remoteScrollTolerance"), "同步滚动命中近似目标时应直接短路，而不是重复 scroll(to:)")
    }

    private func sourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/WorkspaceTextEditorView.swift")
    }
}
