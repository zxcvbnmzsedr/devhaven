import XCTest
import SwiftUI
import AppKit
@testable import DevHavenApp
@testable import DevHavenCore

@MainActor
final class WorkspaceTerminalPaneFocusTests: XCTestCase {
    func testNewFocusedPaneBecomesWindowFirstResponderAfterSplitLikeUpdate() throws {
        let model1 = GhosttySurfaceHostModel(request: makeRequest(paneID: "pane-1"))
        let model2 = GhosttySurfaceHostModel(request: makeRequest(paneID: "pane-2"))

        func rootView(showSecondPane: Bool) -> some View {
            HStack(spacing: 0) {
                paneView(
                    paneID: "pane-1",
                    model: model1,
                    isFocused: !showSecondPane
                )
                if showSecondPane {
                    paneView(
                        paneID: "pane-2",
                        model: model2,
                        isFocused: true
                    )
                }
            }
            .frame(width: 960, height: 640)
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        defer {
            window.orderOut(nil)
        }

        let hostingView = NSHostingView(rootView: rootView(showSecondPane: false))
        window.contentView = hostingView
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        pumpMainRunLoop(ticks: 20)

        let initialSurfaceView = try XCTUnwrap(model1.currentSurfaceView)
        XCTAssertTrue(
            initialSurfaceView.ownsWindowFirstResponder,
            "初始单 pane 挂载完成后，应由当前 terminal pane 持有 firstResponder；实际 responder=\(String(describing: window.firstResponder))"
        )

        hostingView.rootView = rootView(showSecondPane: true)
        pumpMainRunLoop(ticks: 40)

        let newSurfaceView = try XCTUnwrap(model2.currentSurfaceView)
        XCTAssertTrue(
            newSurfaceView.ownsWindowFirstResponder,
            "新增 pane 成为逻辑焦点后，应把窗口 firstResponder 切到新 pane，避免 split 后继续把输入打到旧 pane；实际 responder=\(String(describing: window.firstResponder))"
        )
    }

    private func paneView(
        paneID: String,
        model: GhosttySurfaceHostModel,
        isFocused: Bool
    ) -> some View {
        let pane = makePaneState(paneID: paneID)
        return WorkspaceTerminalPaneView(
            pane: pane,
            selectedItem: pane.selectedItem ?? pane.items[0],
            terminalModel: model,
            surfaceActivity: WorkspaceSurfaceActivity(isVisible: true, isFocused: isFocused),
            isFocused: isFocused,
            isZoomed: false,
            onFocusPane: { _ in },
            onSelectItem: { _, _ in },
            onCreateItem: { _ in },
            onCreateBrowserItem: { _ in },
            onCloseItem: { _, _ in },
            onClosePane: { _ in },
            onSplitPane: { _, _ in },
            onFocusDirection: { _, _ in },
            onResizePane: { _, _, _ in },
            onEqualize: { _ in },
            onToggleZoom: { _ in },
            onSurfaceExit: { _ in },
            onUpdateTabTitle: { _ in },
            onNewTab: { false },
            onCloseTabAction: { _ in false },
            onGotoTabAction: { _ in false },
            onMoveTabAction: { _ in false }
        )
    }

    private func makePaneState(paneID: String) -> WorkspacePaneState {
        let item = WorkspacePaneItemState(
            request: makeRequest(paneID: paneID),
            title: "终端"
        )
        return WorkspacePaneState(
            paneId: paneID,
            items: [item],
            selectedItemId: item.id
        )
    }

    private func makeRequest(paneID: String) -> WorkspaceTerminalLaunchRequest {
        WorkspaceTerminalLaunchRequest(
            projectPath: FileManager.default.homeDirectoryForCurrentUser.path,
            workspaceId: "workspace:test",
            tabId: "tab:test",
            paneId: paneID,
            surfaceId: "surface:\(paneID)",
            terminalSessionId: "session:\(paneID)"
        )
    }

    private func pumpMainRunLoop(ticks: Int) {
        for _ in 0..<ticks {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }
}
