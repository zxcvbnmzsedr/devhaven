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

        let model = makeManagedHostModel()
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

        let view = try makeInteractiveSurfaceView()

        view.keyDown(with: makeKeyEvent(characters: "z", charactersIgnoringModifiers: "z", keyCode: 6))
        view.keyDown(with: makeKeyEvent(characters: "v", charactersIgnoringModifiers: "v", keyCode: 9))
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        let visibleText = view.debugVisibleText()
        XCTAssertTrue(visibleText.contains("zv"), "当前可见文本里应能看到一次 zv，实际：\(visibleText)")
        XCTAssertFalse(visibleText.contains("zvzv"), "输入 zv 不应被重复回显成 zvzv，实际：\(visibleText)")
    }

    func testGhosttyPromptInputDoesNotAppendPromptRedrawArtifactsForPwd() throws {
        try requireSmokeEnabled()

        let view = try makeInteractiveSurfaceView()

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

        let view = try makeInteractiveSurfaceView()

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

    func testAcquireSurfaceViewBridgesNotificationTaskStatusAndBellCallbacks() {
        let model = makeManagedHostModel()
        var receivedNotification: (String, String)?
        var statuses: [WorkspaceTaskStatus] = []
        var bellCount = 0

        model.onNotificationEvent = { title, body in
            receivedNotification = (title, body)
        }
        model.onTaskStatusChange = { status in
            statuses.append(status)
        }
        model.onBell = {
            bellCount += 1
        }

        let view = model.acquireSurfaceView()
        view.bridge.onDesktopNotification?("任务完成", "构建通过")
        view.bridge.onTaskStatusChange?(.running)
        view.bridge.onTaskStatusChange?(.idle)
        view.bridge.onBell?()

        XCTAssertEqual(receivedNotification?.0, "任务完成")
        XCTAssertEqual(receivedNotification?.1, "构建通过")
        XCTAssertEqual(statuses, [.running, .idle])
        XCTAssertEqual(model.taskStatus, .idle)
        XCTAssertEqual(model.bellCount, 1)
        XCTAssertEqual(bellCount, 1)
    }

    func testAcquireSurfaceViewInjectsAgentSignalDirectoryAndAgentResourcePath() {
        let resourcesRootURL = try! FileManager.default.createTemporaryDirectoryForTests()
        let agentResourcesURL = resourcesRootURL
            .appending(path: DevHavenAppResourceLocator.resourceBundleName, directoryHint: .isDirectory)
            .appending(path: "AgentResources", directoryHint: .isDirectory)
        let agentBinURL = agentResourcesURL.appending(path: "bin", directoryHint: .isDirectory)
        try! FileManager.default.createDirectory(at: agentBinURL, withIntermediateDirectories: true)

        let environment = GhosttyRuntimeEnvironmentBuilder.build(
            baseEnvironment: makeRequest().environment,
            agentResourcesURL: agentResourcesURL,
            processEnvironment: [:]
        )

        XCTAssertEqual(
            environment["DEVHAVEN_AGENT_RESOURCES_DIR"],
            agentResourcesURL.path
        )
        XCTAssertEqual(
            environment["DEVHAVEN_AGENT_BIN_DIR"],
            agentBinURL.path
        )
        XCTAssertTrue(
            environment["DEVHAVEN_AGENT_SIGNAL_DIR"]?.contains(".devhaven/agent-status/sessions") == true
        )
        XCTAssertTrue(
            environment["PATH"] == agentBinURL.path
                || environment["PATH"]?.hasPrefix(agentBinURL.path + ":") == true
        )
    }

    func testGhosttyControlDExitTearsDownSurfaceWithoutLockingHost() throws {
        try requireSmokeEnabled()

        let model = makeManagedHostModel()
        let view = try makeInteractiveSurfaceView(model: model)

        view.debugHandleProcessClosed(processAlive: false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        XCTAssertNil(view.surface, "Ctrl+D 导致 shell 退出后，surface 应被主动释放，避免卡死")
        XCTAssertEqual(model.processState, .exited)
        XCTAssertEqual(model.terminalStatusText, "终端已退出")
    }

    func testPrepareForContainerReuseYieldsWindowFirstResponderWhenSurfaceViewOwnsResponder() {
        let model = makeManagedHostModel()
        let view = model.acquireSurfaceView()
        let window = makeWindow()
        window.contentView = view
        retainWindow(window)

        let activator = InitialWindowActivator(application: AppKitApplicationActivationProxy())
        activator.activateIfNeeded(window: AppKitWindowActivationProxy(window: window))
        XCTAssertTrue(window.makeFirstResponder(view))
        XCTAssertTrue(window.firstResponder === view)

        view.prepareForContainerReuse()

        XCTAssertFalse(window.firstResponder === view, "container reuse 前应先让旧 pane 释放 firstResponder，避免分屏重挂载时带着旧焦点进新容器")
    }

    func testRequestFocusRetriesWhenFirstResponderAssignmentMissesFirstAttempt() {
        let model = makeManagedHostModel()
        let view = model.acquireSurfaceView()
        let window = FocusRetryWindow()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 960, height: 640))
        let button = NSButton(title: "Open", target: nil, action: nil)
        button.frame = NSRect(x: 20, y: 20, width: 120, height: 32)
        view.frame = container.bounds
        container.addSubview(view)
        container.addSubview(button)
        window.contentView = container
        retainWindow(window)

        let activator = InitialWindowActivator(application: AppKitApplicationActivationProxy())
        activator.activateIfNeeded(window: AppKitWindowActivationProxy(window: window))
        XCTAssertTrue(window.makeFirstResponder(button))
        XCTAssertTrue(window.firstResponder === button)

        view.requestFocus()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        XCTAssertGreaterThanOrEqual(
            window.surfaceFocusAttemptCount,
            2,
            "首次 makeFirstResponder 没接住时，仍应继续补焦点，避免新开项目或新 pane 时 terminal 没拿到输入焦点"
        )
        XCTAssertTrue(window.firstResponder === view)
    }

    func testRestoreWindowResponderCanReclaimFocusedPaneFromNonTerminalResponderAfterMissedInitialFocus() {
        let model = makeManagedHostModel()
        let view = model.acquireSurfaceView()
        let window = FocusRetryWindow()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 960, height: 640))
        let button = NSButton(title: "Split", target: nil, action: nil)
        button.frame = NSRect(x: 20, y: 20, width: 120, height: 32)
        view.frame = container.bounds
        container.addSubview(view)
        container.addSubview(button)
        window.contentView = container
        retainWindow(window)

        let activator = InitialWindowActivator(application: AppKitApplicationActivationProxy())
        activator.activateIfNeeded(window: AppKitWindowActivationProxy(window: window))
        XCTAssertTrue(window.makeFirstResponder(button))
        XCTAssertTrue(window.firstResponder === button)

        model.syncSurfaceActivity(isVisible: true, isFocused: true)
        model.syncPreferredFocusTransition(preferredFocus: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(window.surfaceFocusAttemptCount, 1, "先模拟首次 terminal 抢焦点失败，复现新开项目/新 pane 后按钮仍占着 responder 的场景")
        XCTAssertTrue(window.firstResponder === button)

        model.restoreWindowResponderIfNeeded()

        XCTAssertTrue(
            window.firstResponder === view,
            "当前 pane 已经是逻辑焦点时，即使首次焦点请求被按钮吃掉，后续也应把 responder 还给 terminal surface"
        )
    }

    private func makeInteractiveSurfaceView(model: GhosttySurfaceHostModel? = nil) throws -> GhosttyTerminalSurfaceView {
        try requireSmokeEnabled()

        let model = model ?? makeManagedHostModel()
        let view = model.acquireSurfaceView()
        guard view.surface != nil else {
            throw XCTSkip("当前 xctest 进程下 Ghostty surface 创建失败：\(model.initializationError ?? "未知错误")")
        }

        let window = makeWindow()
        window.contentView = view
        retainWindow(window)
        let activator = InitialWindowActivator(application: AppKitApplicationActivationProxy())
        activator.activateIfNeeded(window: AppKitWindowActivationProxy(window: window))
        window.makeFirstResponder(view)
        window.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        return view
    }

    private func makeManagedHostModel() -> GhosttySurfaceHostModel {
        let model = GhosttySurfaceHostModel(request: makeRequest())
        addTeardownBlock { @MainActor in
            model.releaseSurface()
        }
        return model
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
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.animationBehavior = .none
        return window
    }

    private func retainWindow(_ window: NSWindow) {
        Self.retainedWindows.append(window)
        addTeardownBlock { @MainActor in
            window.orderOut(nil)
            window.contentView = nil
            Self.retainedWindows.removeAll { $0 === window }
        }
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

private extension FileManager {
    func createTemporaryDirectoryForTests() throws -> URL {
        let rootURL = temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try createDirectory(at: rootURL, withIntermediateDirectories: true)
        return rootURL
    }
}

@MainActor
private final class FocusRetryWindow: NSWindow {
    private(set) var surfaceFocusAttemptCount = 0

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        animationBehavior = .none
    }

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        if responder is GhosttyTerminalSurfaceView {
            surfaceFocusAttemptCount += 1
            if surfaceFocusAttemptCount == 1 {
                return false
            }
        }
        return super.makeFirstResponder(responder)
    }
}
