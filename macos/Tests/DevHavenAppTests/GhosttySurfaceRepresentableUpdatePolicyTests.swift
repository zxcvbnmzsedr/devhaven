import XCTest
import AppKit
@testable import DevHavenApp
@testable import DevHavenCore

@MainActor
final class GhosttySurfaceRepresentableUpdatePolicyTests: XCTestCase {
    func testRepresentableUpdateDoesNotApplyHostSyncByDefault() {
        XCTAssertFalse(GhosttySurfaceRepresentableUpdatePolicy.shouldApplyLatestModelStateOnUpdate)
    }

    func testResolvedSurfaceViewCreatesFreshModelsSurfaceWhenCurrentSurfaceIsMissing() {
        let model = GhosttySurfaceHostModel(request: makeRequest(paneID: "pane:fresh"))
        defer { model.releaseSurface() }

        XCTAssertNil(model.currentSurfaceView)

        let resolved = GhosttySurfaceRepresentableUpdatePolicy.resolvedSurfaceView(
            for: model,
            preferredFocus: false,
            prepareForAttachment: false
        )

        XCTAssertTrue(model.currentSurfaceView === resolved)
    }

    func testResolvedSurfaceViewReusesExistingSurfaceWhenModelAlreadyOwnsOne() {
        let model = GhosttySurfaceHostModel(request: makeRequest(paneID: "pane:existing"))
        defer { model.releaseSurface() }
        let existing = model.acquireSurfaceView(preferredFocus: false)

        let resolved = GhosttySurfaceRepresentableUpdatePolicy.resolvedSurfaceView(
            for: model,
            preferredFocus: true,
            prepareForAttachment: false
        )

        XCTAssertTrue(existing === resolved)
    }

    func testResolvedSurfaceViewPreparesExistingSurfaceForContainerReuse() {
        let model = GhosttySurfaceHostModel(request: makeRequest(paneID: "pane:reuse"))
        defer { model.releaseSurface() }
        let existing = model.acquireSurfaceView(preferredFocus: false)
        let window = makeWindow()
        window.contentView = existing
        retainWindow(window)

        let activator = InitialWindowActivator(application: AppKitApplicationActivationProxy())
        activator.activateIfNeeded(window: AppKitWindowActivationProxy(window: window))
        XCTAssertTrue(window.makeFirstResponder(existing))
        XCTAssertTrue(window.firstResponder === existing)

        let resolved = GhosttySurfaceRepresentableUpdatePolicy.resolvedSurfaceView(
            for: model,
            preferredFocus: true,
            prepareForAttachment: true
        )

        XCTAssertTrue(existing === resolved)
        XCTAssertFalse(
            window.firstResponder === existing,
            "已有 surface 被复用到新的 split/container 前，应先走 prepareForContainerReuse 释放旧 firstResponder；否则带着旧焦点重挂载时容易把原 pane 画面拖成空白/消失"
        )
    }

    private func makeRequest(paneID: String) -> WorkspaceTerminalLaunchRequest {
        WorkspaceTerminalLaunchRequest(
            projectPath: "/tmp/devhaven",
            workspaceId: "workspace:test",
            tabId: "tab:test",
            paneId: paneID,
            surfaceId: "surface:\(paneID)",
            terminalSessionId: "session:\(paneID)"
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

    private func retainWindow(_ window: NSWindow) {
        WindowRetainer.retainedWindows.append(window)
    }
}

@MainActor
private enum WindowRetainer {
    static var retainedWindows: [NSWindow] = []
}
