import XCTest

final class GhosttySurfaceLifecycleLoggingIntegrationTests: XCTestCase {
    func testGhosttyTerminalViewRecordsRepresentableLifecycleLogs() throws {
        let source = try String(contentsOf: terminalViewSourceURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("GhosttySurfaceLifecycleDiagnostics.shared.recordRepresentableMake"),
            "makeNSView 应记录 representable 创建日志，后续才能知道 split/container 重挂时是否走了 attachment 路径"
        )
        XCTAssertTrue(
            source.contains("GhosttySurfaceLifecycleDiagnostics.shared.recordRepresentableUpdate"),
            "updateNSView 应记录 update 日志，后续才能区分是 make 阶段还是 update 阶段触发了 surface swap"
        )
    }

    func testGhosttySurfaceHostRecordsAcquireAttachAndFocusLogs() throws {
        let source = try String(contentsOf: surfaceHostSourceURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("GhosttySurfaceLifecycleDiagnostics.shared.recordSurfaceAcquire"),
            "acquireSurfaceView 应记录是新建还是复用 surface，后续才能排查旧 pane 是否被错误复用"
        )
        XCTAssertTrue(
            source.contains("GhosttySurfaceLifecycleDiagnostics.shared.recordSurfaceAttached"),
            "surfaceViewDidAttach 应记录 attach 时窗口/焦点状态，后续才能排查 attachment-sensitive replay 是否缺失"
        )
        XCTAssertTrue(
            source.contains("GhosttySurfaceLifecycleDiagnostics.shared.recordFocusRequestDecision"),
            "requestFocusIfNeeded 应记录焦点策略输入与决策，后续才能判断为何某次 split 后没有把 responder 还给目标 pane"
        )
        XCTAssertTrue(
            source.contains("GhosttySurfaceLifecycleDiagnostics.shared.recordRestoreWindowResponder"),
            "restoreWindowResponderIfNeeded 应记录执行/跳过原因，后续才能排查旧 responder 是否长期卡在非 terminal 控件上"
        )
    }

    func testGhosttySurfaceViewRecordsReusePreparationLog() throws {
        let source = try String(contentsOf: surfaceViewSourceURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("GhosttySurfaceLifecycleDiagnostics.shared.recordPrepareForContainerReuse"),
            "prepareForContainerReuse 应记录 reuse 前的 responder/窗口状态，后续才能判断旧 surface 是否带着旧焦点重挂"
        )
        XCTAssertTrue(
            source.contains("GhosttySurfaceLifecycleDiagnostics.shared.recordResizeDecision"),
            "updateSurfaceMetrics 应记录 resize 决策，后续才能判断 pane 消失前是否曾被压成异常 backing size 或被 policy 跳过"
        )
    }

    private func terminalViewSourceURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/Ghostty/GhosttyTerminalView.swift")
    }

    private func surfaceHostSourceURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/Ghostty/GhosttySurfaceHost.swift")
    }

    private func surfaceViewSourceURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/Ghostty/GhosttySurfaceView.swift")
    }
}
