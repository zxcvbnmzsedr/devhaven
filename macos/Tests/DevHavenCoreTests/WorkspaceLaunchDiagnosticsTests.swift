import XCTest
@testable import DevHavenCore

@MainActor
final class WorkspaceLaunchDiagnosticsTests: XCTestCase {
    func testEntryRequestedEventIncludesWorkspaceAndPaneCounts() throws {
        var capturedEvents = [WorkspaceLaunchDiagnosticEvent]()
        let now = 100.0
        let diagnostics = WorkspaceLaunchDiagnostics(
            now: { now },
            logSink: { _ in },
            eventSink: { capturedEvents.append($0) }
        )

        var workspace = WorkspaceSessionState(
            projectPath: "/tmp/devhaven",
            workspaceId: "workspace:test"
        )
        workspace.createTab()
        workspace.splitFocusedPane(direction: .right)

        diagnostics.recordEntryRequested(workspace: workspace, openSessionCount: 3)

        XCTAssertEqual(
            capturedEvents,
            [
                .entryRequested(
                    workspaceId: "workspace:test",
                    projectPath: "/tmp/devhaven",
                    openSessionCount: 3,
                    tabCount: 2,
                    paneCount: 3
                ),
            ]
        )
    }

    func testSurfaceCreationFinishedEventIncludesDurationAndStatus() throws {
        var capturedEvents = [WorkspaceLaunchDiagnosticEvent]()
        var now = 10.0
        let diagnostics = WorkspaceLaunchDiagnostics(
            now: { now },
            logSink: { _ in },
            eventSink: { capturedEvents.append($0) }
        )
        let request = WorkspaceTerminalLaunchRequest(
            projectPath: "/tmp/devhaven",
            workspaceId: "workspace:test",
            tabId: "workspace:test/tab:1",
            paneId: "workspace:test/pane:1",
            surfaceId: "workspace:test/surface:1",
            terminalSessionId: "workspace:test/session:1"
        )

        diagnostics.recordSurfaceCreationStarted(request: request)
        now = 10.375
        diagnostics.recordSurfaceCreationFinished(
            request: request,
            status: .failed,
            errorDescription: "surface failed"
        )

        XCTAssertEqual(capturedEvents.count, 2)
        XCTAssertEqual(
            capturedEvents[0],
            .surfaceCreationStarted(
                workspaceId: "workspace:test",
                projectPath: "/tmp/devhaven",
                tabId: "workspace:test/tab:1",
                paneId: "workspace:test/pane:1",
                surfaceId: "workspace:test/surface:1"
            )
        )
        XCTAssertEqual(
            capturedEvents[1],
            .surfaceCreationFinished(
                workspaceId: "workspace:test",
                projectPath: "/tmp/devhaven",
                tabId: "workspace:test/tab:1",
                paneId: "workspace:test/pane:1",
                surfaceId: "workspace:test/surface:1",
                durationMs: 375,
                status: .failed,
                errorDescription: "surface failed"
            )
        )
    }
}
