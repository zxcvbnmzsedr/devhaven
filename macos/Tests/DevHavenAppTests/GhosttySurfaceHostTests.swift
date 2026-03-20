import XCTest
import AppKit
import SwiftUI
import GhosttyKit
@testable import DevHavenApp
@testable import DevHavenCore

@MainActor
final class GhosttySurfaceHostTests: XCTestCase {
    private static var retainedWindows: [NSWindow] = []

    func testGhosttySurfaceAppearanceReadsBackgroundAndOpacityFromConfigFile() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let configURL = directoryURL.appendingPathComponent("ghostty.conf")
        try """
        background = #112233
        background-opacity = 0.67
        """.write(to: configURL, atomically: true, encoding: .utf8)

        guard let config = ghostty_config_new() else {
            XCTFail("ghostty_config_new 返回 nil")
            return
        }
        defer { ghostty_config_free(config) }

        configURL.path.withCString { pointer in
            ghostty_config_load_file(config, pointer)
        }
        ghostty_config_finalize(config)

        let appearance = GhosttySurfaceAppearance(config: config)
        XCTAssertEqual(appearance.backgroundRed, 0x11 / 255.0, accuracy: 0.0001)
        XCTAssertEqual(appearance.backgroundGreen, 0x22 / 255.0, accuracy: 0.0001)
        XCTAssertEqual(appearance.backgroundBlue, 0x33 / 255.0, accuracy: 0.0001)
        XCTAssertEqual(appearance.backgroundOpacity, 0.67, accuracy: 0.0001)
    }

    func testGhosttyRuntimeCanCreateTerminalSurfaceOrExposeInitializationError() throws {
        try requireSmokeEnabled()

        let model = GhosttySurfaceHostModel(request: makeRequest())
        let view = model.acquireSurfaceView()

        if view.surface == nil {
            XCTAssertEqual(model.initializationError, GhosttySurfaceHostError.surfaceCreationFailed.localizedDescription)
            return
        }

        XCTAssertNil(view.initializationError)
        XCTAssertNil(model.initializationError)
    }

    func testGhosttyPrintableInputDoesNotDuplicateCharacters() throws {
        try requireSmokeEnabled()

        let (_, view) = try makeInteractiveSurfaceView()

        view.keyDown(with: makeKeyEvent(characters: "z", charactersIgnoringModifiers: "z", keyCode: 6))
        view.keyDown(with: makeKeyEvent(characters: "v", charactersIgnoringModifiers: "v", keyCode: 9))
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        let visibleText = view.debugVisibleText()
        XCTAssertTrue(visibleText.contains("zv"), "当前可见文本里应能看到一次 zv，实际：\(visibleText)")
        XCTAssertFalse(visibleText.contains("zvzv"), "输入 zv 不应被重复回显成 zvzv，实际：\(visibleText)")
    }

    func testGhosttyPromptInputDoesNotAppendPromptRedrawArtifactsForPwd() throws {
        try requireSmokeEnabled()

        let (_, view) = try makeInteractiveSurfaceView()

        let events = [
            makeKeyEvent(characters: "p", charactersIgnoringModifiers: "p", keyCode: 35),
            makeKeyEvent(characters: "w", charactersIgnoringModifiers: "w", keyCode: 13),
            makeKeyEvent(characters: "d", charactersIgnoringModifiers: "d", keyCode: 2),
            makeKeyEvent(characters: "\r", charactersIgnoringModifiers: "\r", keyCode: 36),
        ]
        for event in events {
            view.keyDown(with: event)
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))

        let visibleText = view.debugVisibleText()
        XCTAssertTrue(visibleText.contains("pwd"), "执行 pwd 后至少应看到一次 pwd 输入回显，实际：\(visibleText)")
        XCTAssertEqual(
            occurrenceCount(of: "pwd", in: visibleText),
            1,
            "真实输入 pwd 只应留下一个 pwd，而不应在 prompt redraw 后残留多个片段，实际：\(visibleText)"
        )
        XCTAssertFalse(visibleText.contains("command not found"), "pwd 不应因为输入错乱而执行成错误命令，实际：\(visibleText)")
        XCTAssertFalse(visibleText.contains("ppwd"), "真实输入 pwd 不应残留 prompt 重绘伪影成 ppwd..., 实际：\(visibleText)")
        XCTAssertFalse(visibleText.contains("pwdpwd"), "真实输入 pwd 不应变成 pwdpwd，实际：\(visibleText)")
        XCTAssertFalse(visibleText.contains("pwdd"), "真实输入 pwd 不应残留 pwdd 一类重绘伪影，实际：\(visibleText)")
    }

    func testGhosttyMarkedTextPreeditDoesNotCommitIntermediateComposition() throws {
        try requireSmokeEnabled()

        let (_, view) = try makeInteractiveSurfaceView()

        let textInputClient: NSTextInputClient = view

        textInputClient.setMarkedText("p", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        textInputClient.setMarkedText("pw", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        textInputClient.setMarkedText("pwd", selectedRange: NSRange(location: 3, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        view.unmarkText()
        view.debugSendText("pwd")
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))

        let visibleText = view.debugVisibleText()
        XCTAssertTrue(visibleText.contains("pwd"), "预编辑提交后应能看到 pwd，实际：\(visibleText)")
        XCTAssertFalse(visibleText.contains("ppw"), "marked text 中间态不应被提前提交，实际：\(visibleText)")
        XCTAssertFalse(visibleText.contains("ppwd"), "预编辑中间态不应堆成 ppwd..., 实际：\(visibleText)")
        XCTAssertFalse(visibleText.contains("pwdpwd"), "预编辑提交后不应重复成 pwdpwd，实际：\(visibleText)")
    }

    func testGhosttyControlDExitTearsDownSurfaceWithoutLockingHost() throws {
        try requireSmokeEnabled()

        let (model, view) = try makeInteractiveSurfaceView()

        view.debugHandleProcessClosed(processAlive: false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        XCTAssertNil(view.surface, "Ctrl+D 导致 shell 退出后，surface 应被主动释放，避免卡死")
        XCTAssertEqual(model.processState, .exited)
        XCTAssertEqual(model.terminalStatusText, "终端已退出")
    }

    private func makeInteractiveSurfaceView() throws -> (GhosttySurfaceHostModel, GhosttyTerminalSurfaceView) {
        try requireSmokeEnabled()

        let model = GhosttySurfaceHostModel(request: makeRequest())
        let view = model.acquireSurfaceView()
        guard view.surface != nil else {
            throw XCTSkip("当前 xctest 进程下 Ghostty surface 创建失败：\(model.initializationError ?? "未知错误")")
        }

        let window = makeWindow()
        window.contentView = view
        Self.retainedWindows.append(window)
        let activator = InitialWindowActivator(application: AppKitApplicationActivationProxy())
        activator.activateIfNeeded(window: AppKitWindowActivationProxy(window: window))
        window.makeFirstResponder(view)
        window.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        return (model, view)
    }

    private func requireSmokeEnabled() throws {
        guard ProcessInfo.processInfo.environment["DEVHAVEN_RUN_GHOSTTY_SMOKE"] == "1" else {
            throw XCTSkip("仅在显式 smoke 场景下运行；设置 DEVHAVEN_RUN_GHOSTTY_SMOKE=1 可启用。")
        }
        guard GhosttyAppRuntime.shared.runtime != nil else {
            throw XCTSkip("Ghostty runtime 未准备完成，当前环境无法运行 smoke。")
        }
    }

    private func makeRequest() -> WorkspaceTerminalLaunchRequest {
        WorkspaceTerminalLaunchRequest(
            projectPath: ProcessInfo.processInfo.environment["DEVHAVEN_PROJECT_PATH"] ?? FileManager.default.homeDirectoryForCurrentUser.path,
            workspaceId: "workspace:test",
            tabId: "tab:test",
            paneId: "pane:test",
            surfaceId: "surface:test",
            terminalSessionId: "session:test"
        )
    }

    private func makeWindow() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
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

    private func occurrenceCount(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }

        var count = 0
        var searchRange: Range<String.Index>? = haystack.startIndex..<haystack.endIndex
        while let range = haystack.range(of: needle, options: [], range: searchRange) {
            count += 1
            searchRange = range.upperBound..<haystack.endIndex
        }
        return count
    }
}
