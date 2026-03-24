import XCTest
@testable import DevHavenApp
@testable import DevHavenCore

@MainActor
final class GhosttySurfaceLifecycleDiagnosticsTests: XCTestCase {
    func testRepresentableMakeEventCapturesAttachmentIntent() {
        var capturedEvents = [GhosttySurfaceLifecycleDiagnosticEvent]()
        var messages = [String]()
        let diagnostics = GhosttySurfaceLifecycleDiagnostics(
            logSink: { messages.append($0) },
            eventSink: { capturedEvents.append($0) }
        )
        let request = makeRequest(paneID: "pane:make")

        diagnostics.recordRepresentableMake(
            request: request,
            preferredFocus: true,
            prepareForAttachment: true
        )

        XCTAssertEqual(
            capturedEvents,
            [
                .representableMake(
                    workspaceId: "workspace:test",
                    tabId: "tab:test",
                    paneId: "pane:make",
                    surfaceId: "surface:pane:make",
                    preferredFocus: true,
                    prepareForAttachment: true
                )
            ]
        )
        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(messages[0].contains("[ghostty-surface] representable-make"))
        XCTAssertTrue(messages[0].contains("prepareForAttachment=true"))
        XCTAssertTrue(messages[0].contains("preferredFocus=true"))
    }

    func testFocusRequestDecisionEventCapturesPolicyInputs() {
        var capturedEvents = [GhosttySurfaceLifecycleDiagnosticEvent]()
        var messages = [String]()
        let diagnostics = GhosttySurfaceLifecycleDiagnostics(
            logSink: { messages.append($0) },
            eventSink: { capturedEvents.append($0) }
        )
        let request = makeRequest(paneID: "pane:focus")

        diagnostics.recordFocusRequestDecision(
            request: request,
            preferredFocus: true,
            wasPreferredFocus: false,
            isSurfaceFocused: false,
            currentEventType: "leftMouseDown",
            shouldRequest: true
        )

        XCTAssertEqual(
            capturedEvents,
            [
                .focusRequestDecision(
                    workspaceId: "workspace:test",
                    tabId: "tab:test",
                    paneId: "pane:focus",
                    surfaceId: "surface:pane:focus",
                    preferredFocus: true,
                    wasPreferredFocus: false,
                    isSurfaceFocused: false,
                    currentEventType: "leftMouseDown",
                    shouldRequest: true
                )
            ]
        )
        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(messages[0].contains("[ghostty-surface] focus-request"))
        XCTAssertTrue(messages[0].contains("event=leftMouseDown"))
        XCTAssertTrue(messages[0].contains("shouldRequest=true"))
    }

    func testResizeDecisionEventCapturesAppliedAndSkippedStates() {
        var capturedEvents = [GhosttySurfaceLifecycleDiagnosticEvent]()
        var messages = [String]()
        let diagnostics = GhosttySurfaceLifecycleDiagnostics(
            logSink: { messages.append($0) },
            eventSink: { capturedEvents.append($0) }
        )
        let request = makeRequest(paneID: "pane:resize")

        diagnostics.recordResizeDecision(
            request: request,
            lastBackingSize: CGSize(width: 320, height: 180),
            newBackingSize: CGSize(width: 640, height: 360),
            cellSizeInPixels: CGSize(width: 8, height: 16),
            applied: true,
            targetWidth: 640,
            targetHeight: 360
        )

        XCTAssertEqual(
            capturedEvents,
            [
                .resizeDecision(
                    workspaceId: "workspace:test",
                    tabId: "tab:test",
                    paneId: "pane:resize",
                    surfaceId: "surface:pane:resize",
                    lastBackingWidth: 320,
                    lastBackingHeight: 180,
                    newBackingWidth: 640,
                    newBackingHeight: 360,
                    cellWidth: 8,
                    cellHeight: 16,
                    applied: true,
                    targetWidth: 640,
                    targetHeight: 360
                )
            ]
        )
        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(messages[0].contains("[ghostty-surface] resize"))
        XCTAssertTrue(messages[0].contains("applied=true"))
        XCTAssertTrue(messages[0].contains("targetWidth=640"))
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
}
