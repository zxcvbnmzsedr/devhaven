import XCTest

final class GhosttySurfaceContextMenuTests: XCTestCase {
    func testSurfaceViewFallsBackToAppKitWhenRightClickIsNotConsumedByGhostty() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("override func rightMouseDown(with event: NSEvent)"),
            "GhosttySurfaceView 应显式接管右键按下，才能区分 Ghostty 捕获与 AppKit contextual menu fallback"
        )
        XCTAssertTrue(
            source.contains("if ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RIGHT, event.ghosttyMods) {") &&
            source.contains("super.rightMouseDown(with: event)"),
            "右键按下应先尝试交给 Ghostty；只有未被消费时才回退到 AppKit 的 rightMouseDown 链路"
        )
        XCTAssertTrue(
            source.contains("if ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_RIGHT, event.ghosttyMods) {") &&
            source.contains("super.rightMouseUp(with: event)"),
            "右键抬起也应保持同样的 fallback 语义，避免按下/抬起链路不一致"
        )
    }

    func testSurfaceViewDefinesCaptureAwareContextMenu() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("override func menu(for event: NSEvent) -> NSMenu?"),
            "GhosttySurfaceView 应实现 menu(for:) 才能在终端选区上弹出原生右键菜单"
        )
        XCTAssertTrue(
            source.contains("guard !ghostty_surface_mouse_captured(surface) else { return nil }"),
            "当 TUI 程序开启 mouse capture 时，不应强行弹出 AppKit 菜单抢走右键事件"
        )
        XCTAssertTrue(
            source.contains("guard event.modifierFlags.contains(.control) else { return nil }") &&
            source.contains("case .leftMouseDown:"),
            "menu(for:) 应同时兼容 macOS 常见的 control + left click contextual menu 手势"
        )
        XCTAssertTrue(
            source.contains("if ghostty_surface_has_selection(surface) {") &&
            source.contains("contextMenuItem(title: \"Copy\", action: #selector(copy(_:)))") &&
            source.contains("contextMenuItem(title: \"Paste\", action: #selector(paste(_:)))") &&
            source.contains("contextMenuItem(title: \"Select All\", action: #selector(selectAll(_:)))"),
            "右键菜单至少应提供 selection-aware 的 Copy，以及 Paste / Select All 这类基础终端操作"
        )
    }

    func testSurfaceViewBridgesStandardMenuSelectorsToGhosttyBindings() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("@IBAction func copy(_ sender: Any?) {") &&
            source.contains("performBindingAction(\"copy_to_clipboard\")"),
            "Copy 菜单项应桥接到 Ghostty 的 copy_to_clipboard binding action"
        )
        XCTAssertTrue(
            source.contains("@IBAction func paste(_ sender: Any?) {") &&
            source.contains("performBindingAction(\"paste_from_clipboard\")"),
            "Paste 菜单项应桥接到 Ghostty 的 paste_from_clipboard binding action"
        )
        XCTAssertTrue(
            source.contains("@IBAction override func selectAll(_ sender: Any?) {") &&
            source.contains("performBindingAction(\"select_all\")"),
            "Select All 菜单项应桥接到 Ghostty 的 select_all binding action"
        )
    }

    private func sourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/Ghostty/GhosttySurfaceView.swift")
    }
}
