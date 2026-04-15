import XCTest
@testable import DevHavenApp
@testable import DevHavenCore

@MainActor
final class WorkspaceMonacoEditorBridgeTests: XCTestCase {
    func testBridgeLoadsLocalMonacoAndAppliesInitialPayload() async throws {
        let bridge = WorkspaceMonacoEditorBridge()
        let payload = makePayload(
            text: "struct Sample {\n    let id: Int\n}\n"
        )

        installBridge(bridge, payload: payload)

        let snapshot = try await waitForSnapshot(on: bridge) { snapshot in
            snapshot.hasEditor && snapshot.text == payload.text
        }
        XCTAssertTrue(snapshot.hasEditor)
        XCTAssertEqual(snapshot.text, payload.text)
        XCTAssertEqual(snapshot.language, "swift")
        XCTAssertEqual(snapshot.readOnly, false)
        XCTAssertEqual(snapshot.lineNumbers, "on")
        XCTAssertEqual(snapshot.wordWrap, "off")
    }

    func testBridgeForwardsContentChangesAndSaveRequests() async throws {
        let bridge = WorkspaceMonacoEditorBridge()
        let payload = makePayload(text: "let value = 1\n")

        let changedExpectation = expectation(description: "Monaco editor change callback")
        let saveExpectation = expectation(description: "Monaco editor save callback")
        var changedText: String?

        installBridge(
            bridge,
            payload: payload,
            onContentChanged: { text in
                changedText = text
                changedExpectation.fulfill()
            },
            onSaveRequested: {
                saveExpectation.fulfill()
            }
        )

        _ = try await waitForSnapshot(on: bridge)

        try await bridge.webView.evaluateJavaScript(
            "window.__devHavenMonacoEditor?.debugSetText?.('let value = 2\\n')"
        )
        try await bridge.webView.evaluateJavaScript(
            "window.__devHavenMonacoEditor?.debugRequestSave?.()"
        )

        await fulfillment(of: [changedExpectation, saveExpectation], timeout: 5.0)
        XCTAssertEqual(changedText, "let value = 2\n")
    }

    func testBridgeGoToLineMovesCaretToRequestedLine() async throws {
        let bridge = WorkspaceMonacoEditorBridge()
        let payload = makePayload(
            text: "one\ntwo\nthree\nfour\n"
        )

        installBridge(bridge, payload: payload)
        _ = try await waitForSnapshot(on: bridge)

        bridge.goToLine(3)

        let snapshot = try await waitForSnapshot(on: bridge) { snapshot in
            snapshot.lineNumber == 3
        }
        XCTAssertEqual(snapshot.lineNumber, 3)
        XCTAssertEqual(snapshot.lastActionId, "editor.action.gotoLine")
    }

    func testBridgeForwardsSearchActionsToMonaco() async throws {
        let bridge = WorkspaceMonacoEditorBridge()
        let payload = makePayload(
            text: "alpha\nbeta\ngamma\n"
        )

        installBridge(bridge, payload: payload)
        _ = try await waitForSnapshot(on: bridge)

        bridge.startSearch()
        var snapshot = try await waitForSnapshot(on: bridge) { snapshot in
            snapshot.lastActionId == "actions.find"
        }
        XCTAssertEqual(snapshot.lastActionId, "actions.find")

        bridge.showReplace()
        snapshot = try await waitForSnapshot(on: bridge) { snapshot in
            snapshot.lastActionId == "editor.action.startFindReplaceAction"
        }
        XCTAssertEqual(snapshot.lastActionId, "editor.action.startFindReplaceAction")

        bridge.findNext()
        snapshot = try await waitForSnapshot(on: bridge) { snapshot in
            snapshot.lastActionId == "editor.action.nextMatchFindAction"
        }
        XCTAssertEqual(snapshot.lastActionId, "editor.action.nextMatchFindAction")

        bridge.findPrevious()
        snapshot = try await waitForSnapshot(on: bridge) { snapshot in
            snapshot.lastActionId == "editor.action.previousMatchFindAction"
        }
        XCTAssertEqual(snapshot.lastActionId, "editor.action.previousMatchFindAction")

        bridge.useSelectionForFind()
        snapshot = try await waitForSnapshot(on: bridge) { snapshot in
            snapshot.lastActionId == "actions.findWithSelection"
        }
        XCTAssertEqual(snapshot.lastActionId, "actions.findWithSelection")

        bridge.closeSearch()
        snapshot = try await waitForSnapshot(on: bridge) { snapshot in
            snapshot.lastActionId == "closeFindWidget"
        }
        XCTAssertEqual(snapshot.lastActionId, "closeFindWidget")
    }

    func testBridgeAppliesDisplayOptionsPayloadUpdates() async throws {
        let bridge = WorkspaceMonacoEditorBridge()
        let payload = makePayload()

        installBridge(bridge, payload: payload)
        _ = try await waitForSnapshot(on: bridge)

        var updatedPayload = payload
        updatedPayload.displayOptions = WorkspaceMonacoEditorDisplayOptionsPayload(
            showsLineNumbers: false,
            highlightsCurrentLine: false,
            usesSoftWraps: true,
            showsWhitespaceCharacters: true,
            showsRightMargin: true,
            rightMarginColumn: 96
        )
        installBridge(bridge, payload: updatedPayload)

        let snapshot = try await waitForSnapshot(on: bridge) { snapshot in
            snapshot.wordWrap == "on"
                && snapshot.lineNumbers == "off"
                && snapshot.renderWhitespace == "all"
                && snapshot.rulers == [96]
        }
        XCTAssertEqual(snapshot.wordWrap, "on")
        XCTAssertEqual(snapshot.lineNumbers, "off")
        XCTAssertEqual(snapshot.renderWhitespace, "all")
        XCTAssertEqual(snapshot.rulers, [96])
    }

    func testBridgeAppliesReadOnlyPayloadState() async throws {
        let bridge = WorkspaceMonacoEditorBridge()
        var payload = makePayload()
        payload.isEditable = false

        installBridge(bridge, payload: payload)

        let snapshot = try await waitForSnapshot(on: bridge) { snapshot in
            snapshot.readOnly == true
        }
        XCTAssertEqual(snapshot.readOnly, true)
    }

    private func installBridge(
        _ bridge: WorkspaceMonacoEditorBridge,
        payload: WorkspaceMonacoEditorPayload,
        onContentChanged: @escaping (String) -> Void = { _ in },
        onSaveRequested: @escaping () -> Void = {}
    ) {
        bridge.update(
            payload: payload,
            onContentChanged: onContentChanged,
            onSaveRequested: onSaveRequested
        )
    }

    private func makePayload(
        text: String = "struct Sample {}\n"
    ) -> WorkspaceMonacoEditorPayload {
        WorkspaceMonacoEditorPayload(
            text: text,
            language: "swift",
            theme: "vs-dark",
            isEditable: true,
            displayOptions: WorkspaceMonacoEditorDisplayOptionsPayload(
                showsLineNumbers: true,
                highlightsCurrentLine: true,
                usesSoftWraps: false,
                showsWhitespaceCharacters: false,
                showsRightMargin: false,
                rightMarginColumn: 120
            )
        )
    }

    private func waitForSnapshot(
        on bridge: WorkspaceMonacoEditorBridge,
        timeout: TimeInterval = 10.0,
        matching predicate: @escaping (MonacoEditorDebugSnapshot) -> Bool = { $0.hasEditor }
    ) async throws -> MonacoEditorDebugSnapshot {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let snapshot = try await debugSnapshot(for: bridge), predicate(snapshot) {
                return snapshot
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        XCTFail("Timed out waiting for Monaco editor to become ready")
        return MonacoEditorDebugSnapshot(
            hasEditor: false,
            text: nil,
            language: nil,
            readOnly: nil,
            lineNumber: nil,
            lastActionId: nil,
            wordWrap: nil,
            lineNumbers: nil,
            renderWhitespace: nil,
            rulers: []
        )
    }

    private func debugSnapshot(for bridge: WorkspaceMonacoEditorBridge) async throws -> MonacoEditorDebugSnapshot? {
        guard let rawSnapshot = try await bridge.webView.evaluateJavaScript(
            "window.__devHavenMonacoEditor?.debugSnapshot?.()"
        ) as? [String: Any] else {
            return nil
        }

        return MonacoEditorDebugSnapshot(
            hasEditor: rawSnapshot["hasEditor"] as? Bool ?? false,
            text: rawSnapshot["text"] as? String,
            language: rawSnapshot["language"] as? String,
            readOnly: rawSnapshot["readOnly"] as? Bool,
            lineNumber: rawSnapshot["lineNumber"] as? Int,
            lastActionId: rawSnapshot["lastActionId"] as? String,
            wordWrap: rawSnapshot["wordWrap"] as? String,
            lineNumbers: rawSnapshot["lineNumbers"] as? String,
            renderWhitespace: rawSnapshot["renderWhitespace"] as? String,
            rulers: (rawSnapshot["rulers"] as? [NSNumber])?.map(\.intValue) ?? []
        )
    }
}

private struct MonacoEditorDebugSnapshot: Equatable {
    var hasEditor: Bool
    var text: String?
    var language: String?
    var readOnly: Bool?
    var lineNumber: Int?
    var lastActionId: String?
    var wordWrap: String?
    var lineNumbers: String?
    var renderWhitespace: String?
    var rulers: [Int]
}
