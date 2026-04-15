import XCTest
@testable import DevHavenApp
@testable import DevHavenCore

@MainActor
final class WorkspaceMonacoDiffBridgeTests: XCTestCase {
    func testBridgeLoadsLocalMonacoAndAppliesInitialPayload() async throws {
        let bridge = WorkspaceMonacoDiffBridge()
        let payload = makePayload(
            originalText: "let value = 1\n",
            modifiedText: "let value = 2\n"
        )

        installBridge(bridge, payload: payload)

        let snapshot = try await waitForSnapshot(on: bridge) { snapshot in
            snapshot.originalText == payload.originalText &&
            snapshot.modifiedText == payload.modifiedText
        }
        XCTAssertTrue(snapshot.hasEditor)
        XCTAssertEqual(snapshot.originalText, payload.originalText)
        XCTAssertEqual(snapshot.modifiedText, payload.modifiedText)
        XCTAssertEqual(snapshot.readOnly, false)
    }

    func testBridgeForwardsContentChangesAndSaveRequests() async throws {
        let bridge = WorkspaceMonacoDiffBridge()
        let payload = makePayload(
            originalText: "struct User {}\n",
            modifiedText: "struct User {\n}\n"
        )

        let changedExpectation = expectation(description: "Monaco change callback")
        let saveExpectation = expectation(description: "Monaco save callback")
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
            "window.__devHavenMonaco?.debugSetModifiedText?.('struct User {\\n    let id: Int\\n}\\n')"
        )
        try await bridge.webView.evaluateJavaScript(
            "window.__devHavenMonaco?.debugRequestSave?.()"
        )

        await fulfillment(of: [changedExpectation, saveExpectation], timeout: 5.0)
        XCTAssertEqual(changedText, "struct User {\n    let id: Int\n}\n")
    }

    func testBridgeRestoresInitialSelectionAfterReady() async throws {
        let bridge = WorkspaceMonacoDiffBridge()
        let payload = makePayload(
            originalText: "line 1\nline 2\nline 3\n",
            modifiedText: "line 1\nline two\nline 3\n",
            blocks: [
                WorkspaceMonacoDiffBlockPayload(
                    id: "compare-block-0",
                    leftStartLine: 1,
                    leftLineCount: 1,
                    rightStartLine: 1,
                    rightLineCount: 1
                )
            ]
        )

        installBridge(
            bridge,
            payload: payload,
            selectedBlockID: "compare-block-0"
        )

        let snapshot = try await waitForSnapshot(on: bridge) { snapshot in
            snapshot.selectedBlockId == "compare-block-0"
        }
        XCTAssertEqual(snapshot.selectedBlockId, "compare-block-0")
    }

    func testBridgeForwardsActiveBlockChangesFromEditorSelection() async throws {
        let bridge = WorkspaceMonacoDiffBridge()
        let payload = makePayload(
            originalText: "alpha\nbeta\ngamma\n",
            modifiedText: "alpha\nbeta updated\ngamma\n",
            blocks: [
                WorkspaceMonacoDiffBlockPayload(
                    id: "compare-block-0",
                    leftStartLine: 1,
                    leftLineCount: 1,
                    rightStartLine: 1,
                    rightLineCount: 1
                )
            ]
        )

        let activeBlockExpectation = expectation(description: "Monaco active block callback")
        var receivedBlockID: String?

        installBridge(
            bridge,
            payload: payload,
            onActiveBlockChanged: { blockID in
                receivedBlockID = blockID
                activeBlockExpectation.fulfill()
            }
        )

        _ = try await waitForSnapshot(on: bridge)

        try await bridge.webView.evaluateJavaScript(
            "window.__devHavenMonaco?.debugSelectLine?.('modified', 2)"
        )

        await fulfillment(of: [activeBlockExpectation], timeout: 5.0)
        XCTAssertEqual(receivedBlockID, "compare-block-0")
    }

    func testBridgeForwardsToolbarActions() async throws {
        let bridge = WorkspaceMonacoDiffBridge()
        let payload = makePayload()

        let previousExpectation = expectation(description: "Previous difference")
        let nextExpectation = expectation(description: "Next difference")
        let refreshExpectation = expectation(description: "Refresh")
        let viewerModeExpectation = expectation(description: "Viewer mode changed")
        var requestedMode: WorkspaceDiffViewerMode?

        installBridge(
            bridge,
            payload: payload,
            onPreviousDifferenceRequested: {
                previousExpectation.fulfill()
            },
            onNextDifferenceRequested: {
                nextExpectation.fulfill()
            },
            onRefreshRequested: {
                refreshExpectation.fulfill()
            },
            onViewerModeChanged: { mode in
                requestedMode = mode
                viewerModeExpectation.fulfill()
            }
        )

        _ = try await waitForSnapshot(on: bridge)

        try await bridge.webView.evaluateJavaScript(
            "window.__devHavenMonaco?.debugTriggerToolbarAction?.('previous')"
        )
        try await bridge.webView.evaluateJavaScript(
            "window.__devHavenMonaco?.debugTriggerToolbarAction?.('next')"
        )
        try await bridge.webView.evaluateJavaScript(
            "window.__devHavenMonaco?.debugTriggerToolbarAction?.('refresh')"
        )
        try await bridge.webView.evaluateJavaScript(
            "window.__devHavenMonaco?.debugTriggerToolbarAction?.('viewerMode', 'unified')"
        )

        await fulfillment(
            of: [previousExpectation, nextExpectation, refreshExpectation, viewerModeExpectation],
            timeout: 5.0
        )
        XCTAssertEqual(requestedMode, .unified)
    }

    func testBridgeAppliesUnifiedViewerModeFromPayloadUpdate() async throws {
        let bridge = WorkspaceMonacoDiffBridge()
        let sideBySidePayload = makePayload()
        installBridge(bridge, payload: sideBySidePayload)

        _ = try await waitForSnapshot(on: bridge) { snapshot in
            snapshot.viewerMode == "sideBySide"
        }

        var unifiedPayload = sideBySidePayload
        unifiedPayload.toolbar.viewerMode = WorkspaceDiffViewerMode.unified.rawValue
        installBridge(bridge, payload: unifiedPayload)

        let snapshot = try await waitForSnapshot(on: bridge) { snapshot in
            snapshot.viewerMode == "unified"
        }
        XCTAssertEqual(snapshot.viewerMode, "unified")
    }

    private func installBridge(
        _ bridge: WorkspaceMonacoDiffBridge,
        payload: WorkspaceMonacoDiffPayload,
        selectedBlockID: String? = nil,
        onContentChanged: @escaping (String) -> Void = { _ in },
        onSaveRequested: @escaping () -> Void = {},
        onActiveBlockChanged: @escaping (String) -> Void = { _ in },
        onPreviousDifferenceRequested: @escaping () -> Void = {},
        onNextDifferenceRequested: @escaping () -> Void = {},
        onRefreshRequested: @escaping () -> Void = {},
        onViewerModeChanged: @escaping (WorkspaceDiffViewerMode) -> Void = { _ in }
    ) {
        bridge.update(
            payload: payload,
            selectedBlockID: selectedBlockID,
            onContentChanged: onContentChanged,
            onSaveRequested: onSaveRequested,
            onActiveBlockChanged: onActiveBlockChanged,
            onPreviousDifferenceRequested: onPreviousDifferenceRequested,
            onNextDifferenceRequested: onNextDifferenceRequested,
            onRefreshRequested: onRefreshRequested,
            onViewerModeChanged: onViewerModeChanged
        )
    }

    private func makePayload(
        originalText: String = "struct Sample {}\n",
        modifiedText: String = "struct Sample {\n    let id: Int\n}\n",
        blocks: [WorkspaceMonacoDiffBlockPayload] = []
    ) -> WorkspaceMonacoDiffPayload {
        WorkspaceMonacoDiffPayload(
            originalText: originalText,
            modifiedText: modifiedText,
            language: "swift",
            theme: "vs-dark",
            toolbar: WorkspaceMonacoDiffToolbarPayload(
                currentDifferenceIndex: blocks.isEmpty ? 0 : 1,
                totalDifferences: blocks.count,
                currentRequestIndex: 1,
                totalRequests: 1,
                canGoPrevious: false,
                canGoNext: !blocks.isEmpty,
                viewerMode: WorkspaceDiffViewerMode.sideBySide.rawValue,
                availableViewerModes: [
                    WorkspaceDiffViewerMode.sideBySide.rawValue,
                    WorkspaceDiffViewerMode.unified.rawValue,
                ],
                compareModeLabel: "Local",
                languageLabel: "Swift",
                isEditable: true
            ),
            leftPane: WorkspaceMonacoDiffPanePayload(
                badge: "Staged",
                fileName: "Sample.swift",
                path: "/tmp/Sample.swift",
                detailText: nil,
                renamedFrom: nil
            ),
            rightPane: WorkspaceMonacoDiffPanePayload(
                badge: "Local",
                fileName: "Sample.swift",
                path: "/tmp/Sample.swift",
                detailText: nil,
                renamedFrom: nil
            ),
            blocks: blocks
        )
    }

    private func waitForSnapshot(
        on bridge: WorkspaceMonacoDiffBridge,
        timeout: TimeInterval = 10.0,
        matching predicate: @escaping (MonacoDebugSnapshot) -> Bool = { $0.hasEditor }
    ) async throws -> MonacoDebugSnapshot {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let snapshot = try await debugSnapshot(for: bridge), predicate(snapshot) {
                return snapshot
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        XCTFail("Timed out waiting for Monaco diff to become ready")
        return MonacoDebugSnapshot(
            hasEditor: false,
            originalText: nil,
            modifiedText: nil,
            readOnly: nil,
            selectedBlockId: nil,
            viewerMode: nil
        )
    }

    private func debugSnapshot(for bridge: WorkspaceMonacoDiffBridge) async throws -> MonacoDebugSnapshot? {
        guard let rawSnapshot = try await bridge.webView.evaluateJavaScript(
            "window.__devHavenMonaco?.debugSnapshot?.()"
        ) as? [String: Any] else {
            return nil
        }

        return MonacoDebugSnapshot(
            hasEditor: rawSnapshot["hasEditor"] as? Bool ?? false,
            originalText: rawSnapshot["originalText"] as? String,
            modifiedText: rawSnapshot["modifiedText"] as? String,
            readOnly: rawSnapshot["readOnly"] as? Bool,
            selectedBlockId: rawSnapshot["selectedBlockId"] as? String,
            viewerMode: rawSnapshot["viewerMode"] as? String
        )
    }
}

private struct MonacoDebugSnapshot: Equatable {
    var hasEditor: Bool
    var originalText: String?
    var modifiedText: String?
    var readOnly: Bool?
    var selectedBlockId: String?
    var viewerMode: String?
}
