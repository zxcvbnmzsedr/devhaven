import XCTest
import AppKit
import GhosttyKit
@testable import DevHavenApp

@MainActor
final class GhosttySurfaceMenuShortcutRoutingPolicyTests: XCTestCase {
    func testCommandShortcutAttemptsMenuBeforeBindings() {
        let event = makeKeyEvent(
            characters: "k",
            charactersIgnoringModifiers: "k",
            keyCode: 40,
            modifierFlags: [.command]
        )

        XCTAssertTrue(
            GhosttySurfaceMenuShortcutRoutingPolicy.shouldAttemptMenuBeforeBindings(for: event),
            "终端聚焦时，带 ⌘ 的应用菜单快捷键应先尝试命中主菜单，避免被 Ghostty 自身绑定抢走"
        )
    }

    func testPlainTypingDoesNotAttemptMenuBeforeBindings() {
        let event = makeKeyEvent(
            characters: "k",
            charactersIgnoringModifiers: "k",
            keyCode: 40
        )

        XCTAssertFalse(
            GhosttySurfaceMenuShortcutRoutingPolicy.shouldAttemptMenuBeforeBindings(for: event),
            "普通输入不应先查主菜单，否则会破坏终端正常打字"
        )
    }

    func testConsumedNonPerformableBindingStillAllowsLateMenuAttempt() {
        let flags = ghostty_binding_flags_e(GHOSTTY_BINDING_FLAGS_CONSUMED.rawValue)

        XCTAssertTrue(
            GhosttySurfaceMenuShortcutRoutingPolicy.shouldAttemptMenuAfterBinding(flags),
            "Ghostty 仅声明 consumed 且不可执行时，仍应允许旧的菜单兜底路径"
        )
    }

    func testPerformableBindingDoesNotUseLateMenuAttempt() {
        let flags = ghostty_binding_flags_e(
            GHOSTTY_BINDING_FLAGS_CONSUMED.rawValue | GHOSTTY_BINDING_FLAGS_PERFORMABLE.rawValue
        )

        XCTAssertFalse(
            GhosttySurfaceMenuShortcutRoutingPolicy.shouldAttemptMenuAfterBinding(flags),
            "Ghostty 自己可执行的绑定不应走旧的 binding 后菜单兜底逻辑"
        )
    }

    func testSurfaceViewAttemptsMenuBeforeGhosttyBindings() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("if GhosttySurfaceMenuShortcutRoutingPolicy.shouldAttemptMenuBeforeBindings(for: event),\n           let menu = NSApp.mainMenu,\n           menu.performKeyEquivalent(with: event) {\n            return true\n        }"),
            "GhosttySurfaceView 应先让主菜单处理 ⌘/⌃ 快捷键，再决定是否把事件交回终端绑定"
        )
    }

    private func makeKeyEvent(
        characters: String,
        charactersIgnoringModifiers: String,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags = []
    ) -> NSEvent {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            isARepeat: false,
            keyCode: keyCode
        ) else {
            fatalError("无法构造测试键盘事件")
        }
        return event
    }

    private func sourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/Ghostty/GhosttySurfaceView.swift")
    }
}
