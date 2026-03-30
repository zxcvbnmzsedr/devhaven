import XCTest
import SwiftUI
import AppKit
@testable import DevHavenApp

@MainActor
final class WorkspaceTextEditorFocusTests: XCTestCase {
    func testFocusRequestPolicyOnlyFiresForNewEditorActivation() {
        XCTAssertTrue(
            WorkspaceTextEditorFocusRequestPolicy.shouldRequestFocus(
                wantsFocus: true,
                hasIssuedFocusRequest: false,
                isEditorFocused: false,
                currentEventType: .leftMouseDown
            )
        )
        XCTAssertFalse(
            WorkspaceTextEditorFocusRequestPolicy.shouldRequestFocus(
                wantsFocus: true,
                hasIssuedFocusRequest: true,
                isEditorFocused: false,
                currentEventType: .leftMouseDown
            )
        )
        XCTAssertFalse(
            WorkspaceTextEditorFocusRequestPolicy.shouldRequestFocus(
                wantsFocus: true,
                hasIssuedFocusRequest: false,
                isEditorFocused: true,
                currentEventType: .leftMouseDown
            )
        )
        XCTAssertFalse(
            WorkspaceTextEditorFocusRequestPolicy.shouldRequestFocus(
                wantsFocus: true,
                hasIssuedFocusRequest: false,
                isEditorFocused: false,
                currentEventType: .leftMouseDragged
            )
        )
    }

    func testTextEditorRequestsFirstResponderWhenFocusRequestTurnsOn() throws {
        func rootView(shouldRequestFocus: Bool) -> some View {
            WorkspaceTextEditorView(
                editorID: "workspace-editor-focus-test",
                text: .constant("alpha\nbeta"),
                isEditable: true,
                shouldRequestFocus: shouldRequestFocus
            )
            .frame(width: 480, height: 320)
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        defer {
            window.orderOut(nil)
        }

        let hostingView = NSHostingView(rootView: rootView(shouldRequestFocus: false))
        window.contentView = hostingView
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        pumpMainRunLoop()

        let initialTextView = try XCTUnwrap(findDescendant(ofType: NSTextView.self, in: hostingView))
        window.makeFirstResponder(nil)
        pumpMainRunLoop()
        XCTAssertFalse(window.firstResponder === initialTextView)

        hostingView.rootView = rootView(shouldRequestFocus: true)
        pumpMainRunLoop()

        let focusedTextView = try XCTUnwrap(findDescendant(ofType: NSTextView.self, in: hostingView))
        XCTAssertTrue(window.firstResponder === focusedTextView)
    }

    private func pumpMainRunLoop(ticks: Int = 8) {
        for _ in 0..<ticks {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
    }

    private func findDescendant<T: NSView>(ofType type: T.Type, in root: NSView) -> T? {
        if let match = root as? T {
            return match
        }
        for subview in root.subviews {
            if let match = findDescendant(ofType: type, in: subview) {
                return match
            }
        }
        return nil
    }
}
