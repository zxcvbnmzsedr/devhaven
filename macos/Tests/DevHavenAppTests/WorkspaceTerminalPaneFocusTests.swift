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

    func testSwitchingSelectedTerminalItemWithinSamePaneTransfersWindowFirstResponder() throws {
        let paneID = "pane-1"
        let firstItem = WorkspacePaneItemState(
            request: makeRequest(paneID: paneID, surfaceSuffix: "a"),
            title: "终端 A"
        )
        let secondItem = WorkspacePaneItemState(
            request: makeRequest(paneID: paneID, surfaceSuffix: "b"),
            title: "终端 B"
        )
        let firstModel = GhosttySurfaceHostModel(request: firstItem.request)
        let secondModel = GhosttySurfaceHostModel(request: secondItem.request)

        func rootView(selectedItemID: String) -> some View {
            let pane = WorkspacePaneState(
                paneId: paneID,
                items: [firstItem, secondItem],
                selectedItemId: selectedItemID
            )
            let activeItem = try! XCTUnwrap(pane.selectedItem)
            return WorkspaceTerminalPaneView(
                pane: pane,
                selectedItem: activeItem,
                terminalModel: activeItem.id == firstItem.id ? firstModel : secondModel,
                surfaceActivity: WorkspaceSurfaceActivity(isVisible: true, isFocused: true),
                isFocused: true,
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

        let hostingView = NSHostingView(rootView: rootView(selectedItemID: firstItem.id))
        window.contentView = hostingView
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        pumpMainRunLoop(ticks: 20)

        let initialSurfaceView = try XCTUnwrap(firstModel.currentSurfaceView)
        XCTAssertTrue(
            initialSurfaceView.ownsWindowFirstResponder,
            "初始 terminal item 挂载后，应持有窗口 firstResponder。"
        )

        hostingView.rootView = rootView(selectedItemID: secondItem.id)
        pumpMainRunLoop(ticks: 40)

        let swappedSurfaceView = try XCTUnwrap(secondModel.currentSurfaceView)
        XCTAssertTrue(
            swappedSurfaceView.ownsWindowFirstResponder,
            "同一 pane 切换到新的 terminal item 后，应把窗口 firstResponder 交给新 surface，避免内容只在失焦后才恢复。"
        )
    }

    func testSwitchingSelectedTerminalItemWithinSamePaneReplaysSurfaceActivityToNewModel() {
        let paneID = "pane-1"
        let firstItem = WorkspacePaneItemState(
            request: makeRequest(paneID: paneID, surfaceSuffix: "a"),
            title: "终端 A"
        )
        let secondItem = WorkspacePaneItemState(
            request: makeRequest(paneID: paneID, surfaceSuffix: "b"),
            title: "终端 B"
        )
        let firstModel = GhosttySurfaceHostModel(request: firstItem.request)
        let secondModel = GhosttySurfaceHostModel(request: secondItem.request)

        func rootView(selectedItemID: String) -> some View {
            let pane = WorkspacePaneState(
                paneId: paneID,
                items: [firstItem, secondItem],
                selectedItemId: selectedItemID
            )
            let activeItem = try! XCTUnwrap(pane.selectedItem)
            return WorkspaceTerminalPaneView(
                pane: pane,
                selectedItem: activeItem,
                terminalModel: activeItem.id == firstItem.id ? firstModel : secondModel,
                surfaceActivity: WorkspaceSurfaceActivity(isVisible: true, isFocused: true),
                isFocused: true,
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

        let hostingView = NSHostingView(rootView: rootView(selectedItemID: firstItem.id))
        window.contentView = hostingView
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        pumpMainRunLoop(ticks: 20)

        XCTAssertEqual(
            firstModel.debugCurrentSurfaceActivity,
            WorkspaceSurfaceActivity(isVisible: true, isFocused: true),
            "初始 terminal item 挂载后，应立即拿到当前 pane 的可见/聚焦状态。"
        )

        hostingView.rootView = rootView(selectedItemID: secondItem.id)
        pumpMainRunLoop(ticks: 40)

        XCTAssertEqual(
            secondModel.debugCurrentSurfaceActivity,
            WorkspaceSurfaceActivity(isVisible: true, isFocused: true),
            "同一 pane 切换到新的 terminal item 后，应重放当前 surface activity，避免首次挂载仍停留在不可见态。"
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

    private func makeRequest(paneID: String, surfaceSuffix: String? = nil) -> WorkspaceTerminalLaunchRequest {
        let suffix = surfaceSuffix ?? paneID
        return WorkspaceTerminalLaunchRequest(
            projectPath: FileManager.default.homeDirectoryForCurrentUser.path,
            workspaceId: "workspace:test",
            tabId: "tab:test",
            paneId: paneID,
            surfaceId: "surface:\(suffix)",
            terminalSessionId: "session:\(suffix)"
        )
    }

    private func pumpMainRunLoop(ticks: Int) {
        for _ in 0..<ticks {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }
}
