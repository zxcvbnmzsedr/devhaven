import XCTest

final class GhosttySurfaceSearchOverlayTests: XCTestCase {
    func testGhosttySurfaceHostDisplaysSearchOverlayWhenSearchIsActive() throws {
        let source = try String(contentsOf: hostSourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("GhosttySurfaceSearchOverlay"),
            "GhosttySurfaceHost 应在终端区域上层叠加搜索浮层"
        )
        XCTAssertTrue(
            source.contains("searchNeedle != nil"),
            "搜索浮层应由 searchNeedle 是否存在来决定显隐，避免再引入第二套真相源"
        )
        XCTAssertTrue(
            source.contains("alignment: .topTrailing"),
            "搜索浮层应固定对齐到 terminal 区域右上角，而不是继续沿用左上角默认布局"
        )
    }

    func testSearchOverlayEmitsGhosttyBindingActions() throws {
        let source = try String(contentsOf: overlaySourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("performBindingAction(\"search:\\(needle)\")"),
            "搜索输入变化后应通过 search:<needle> binding action 发给 libghostty"
        )
        XCTAssertTrue(
            source.contains("performBindingAction(\"end_search\")"),
            "关闭搜索时应显式发送 end_search binding action"
        )
        XCTAssertTrue(
            source.contains("requestFocus()"),
            "关闭搜索后应把焦点还给 terminal surface，避免键盘留在浮层输入框上"
        )
    }

    private func hostSourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/Ghostty/GhosttySurfaceHost.swift")
    }

    private func overlaySourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/Ghostty/GhosttySurfaceSearchOverlay.swift")
    }
}
