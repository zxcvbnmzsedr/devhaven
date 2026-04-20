import XCTest
@testable import DevHavenCore

@MainActor
final class WorkspaceAttentionControllerTests: XCTestCase {
    func testRecordAgentSignalRemapsSurfaceToCurrentPane() throws {
        let projectPath = "/tmp/project"
        let workspaceController = GhosttyWorkspaceController(projectPath: projectPath)
        let sourcePaneID = try XCTUnwrap(workspaceController.selectedPane?.id)
        let movedItem = try XCTUnwrap(workspaceController.createTerminalItem(inPane: sourcePaneID))
        let targetPane = try XCTUnwrap(workspaceController.splitFocusedPane(direction: .right))
        _ = try XCTUnwrap(
            workspaceController.movePaneItem(
                movedItem.id,
                from: sourcePaneID,
                to: targetPane.id,
                at: 1
            )
        )

        let harness = WorkspaceAttentionControllerHarness(projectPath: projectPath, controller: workspaceController)

        harness.attentionController.recordAgentSignal(
            WorkspaceAgentSessionSignal(
                projectPath: projectPath,
                workspaceId: workspaceController.workspaceId,
                tabId: try XCTUnwrap(workspaceController.selectedTabId),
                paneId: sourcePaneID,
                surfaceId: movedItem.id,
                terminalSessionId: movedItem.request.terminalSessionId,
                agentKind: .codex,
                sessionId: "session-1",
                state: .running,
                summary: "running",
                updatedAt: Date(timeIntervalSinceReferenceDate: 42)
            )
        )

        XCTAssertEqual(
            harness.attentionController.codexDisplayCandidates(),
            [
                WorkspaceAgentDisplayCandidate(
                    projectPath: projectPath,
                    paneID: targetPane.id,
                    signalSessionID: "session-1",
                    signalState: .running,
                    signalPhase: .thinking,
                    signalUpdatedAt: Date(timeIntervalSinceReferenceDate: 42)
                )
            ]
        )
        XCTAssertEqual(harness.codexCandidateRevision, 1)
    }

    func testSyncAttentionStateWithOpenSessionsPrunesClosedProjectsAndOverrides() {
        let openProjectPath = "/tmp/open-project"
        let closedProjectPath = "/tmp/closed-project"
        let harness = WorkspaceAttentionControllerHarness(projectPath: openProjectPath)
        harness.openProjectPaths = [openProjectPath]
        harness.attentionStatesByProjectPath = [
            openProjectPath: WorkspaceAttentionState(
                taskStatusByPaneID: ["pane-open": .running]
            ),
            closedProjectPath: WorkspaceAttentionState(
                taskStatusByPaneID: ["pane-closed": .running]
            ),
        ]
        harness.agentDisplayOverridesByProjectPath = [
            openProjectPath: [
                "pane-open": WorkspaceAgentPresentationOverride(state: .running, summary: "open"),
            ],
            closedProjectPath: [
                "pane-closed": WorkspaceAgentPresentationOverride(state: .waiting, summary: "closed"),
            ],
        ]

        harness.attentionController.syncAttentionStateWithOpenSessions()

        XCTAssertEqual(Set(harness.attentionStatesByProjectPath.keys), [openProjectPath])
        XCTAssertEqual(Set(harness.agentDisplayOverridesByProjectPath.keys), [openProjectPath])
    }

    func testReplaceWorkspaceAgentDisplayOverridesKeepsOnlyVisibleCodexPane() {
        let projectPath = "/tmp/project"
        let workspaceController = GhosttyWorkspaceController(projectPath: projectPath)
        let hiddenTab = workspaceController.createTab()
        let visibleTab = workspaceController.createTab()
        let harness = WorkspaceAttentionControllerHarness(projectPath: projectPath, controller: workspaceController)

        harness.attentionController.recordAgentSignal(
            WorkspaceAgentSessionSignal(
                projectPath: projectPath,
                workspaceId: "workspace",
                tabId: hiddenTab.id,
                paneId: hiddenTab.focusedPaneId,
                surfaceId: "surface-hidden",
                terminalSessionId: "terminal-hidden",
                agentKind: .codex,
                sessionId: "session-hidden",
                state: .waiting,
                phase: .awaitingInput,
                attention: .input,
                summary: "hidden waiting",
                updatedAt: Date(timeIntervalSinceReferenceDate: 100)
            )
        )
        harness.attentionController.recordAgentSignal(
            WorkspaceAgentSessionSignal(
                projectPath: projectPath,
                workspaceId: "workspace",
                tabId: visibleTab.id,
                paneId: visibleTab.focusedPaneId,
                surfaceId: "surface-visible",
                terminalSessionId: "terminal-visible",
                agentKind: .codex,
                sessionId: "session-visible",
                state: .running,
                phase: .thinking,
                summary: "visible running",
                updatedAt: Date(timeIntervalSinceReferenceDate: 200)
            )
        )

        harness.attentionController.replaceWorkspaceAgentDisplayOverrides(
            [
                projectPath: [
                    hiddenTab.focusedPaneId: WorkspaceAgentPresentationOverride(
                        state: .waiting,
                        phase: .awaitingInput,
                        attention: .input,
                        summary: "hidden override"
                    ),
                    visibleTab.focusedPaneId: WorkspaceAgentPresentationOverride(
                        state: .running,
                        phase: .thinking,
                        summary: "visible override"
                    ),
                ],
            ]
        )

        XCTAssertEqual(
            harness.agentDisplayOverridesByProjectPath,
            [
                projectPath: [
                    visibleTab.focusedPaneId: WorkspaceAgentPresentationOverride(
                        state: .running,
                        phase: .thinking,
                        summary: "visible override"
                    ),
                ],
            ]
        )
    }
}

@MainActor
private final class WorkspaceAttentionControllerHarness {
    private final class StateBox {
        var openProjectPaths: [String]
        var activeProjectPath: String?
        var notificationsEnabled = true
        var attentionStatesByProjectPath: [String: WorkspaceAttentionState] = [:]
        var agentDisplayOverridesByProjectPath: [String: [String: WorkspaceAgentPresentationOverride]] = [:]
        var codexCandidates: [WorkspaceAgentDisplayCandidate] = []
        var codexCandidateRevision = 0
        var reportedErrors: [String?] = []

        init(projectPath: String) {
            self.openProjectPaths = [projectPath]
            self.activeProjectPath = projectPath
        }
    }

    private let state: StateBox

    var openProjectPaths: [String] {
        get { state.openProjectPaths }
        set { state.openProjectPaths = newValue }
    }

    var activeProjectPath: String? {
        get { state.activeProjectPath }
        set { state.activeProjectPath = newValue }
    }

    var notificationsEnabled: Bool {
        get { state.notificationsEnabled }
        set { state.notificationsEnabled = newValue }
    }

    var attentionStatesByProjectPath: [String: WorkspaceAttentionState] {
        get { state.attentionStatesByProjectPath }
        set { state.attentionStatesByProjectPath = newValue }
    }

    var agentDisplayOverridesByProjectPath: [String: [String: WorkspaceAgentPresentationOverride]] {
        get { state.agentDisplayOverridesByProjectPath }
        set { state.agentDisplayOverridesByProjectPath = newValue }
    }

    var codexCandidates: [WorkspaceAgentDisplayCandidate] {
        get { state.codexCandidates }
        set { state.codexCandidates = newValue }
    }

    var codexCandidateRevision: Int {
        get { state.codexCandidateRevision }
        set { state.codexCandidateRevision = newValue }
    }

    var reportedErrors: [String?] {
        get { state.reportedErrors }
        set { state.reportedErrors = newValue }
    }

    let controllerByProjectPath: [String: GhosttyWorkspaceController]
    let sessionByProjectPath: [String: OpenWorkspaceSessionState]
    let attentionController: WorkspaceAttentionController

    init(projectPath: String, controller: GhosttyWorkspaceController? = nil) {
        let resolvedController = controller ?? GhosttyWorkspaceController(projectPath: projectPath)
        let state = StateBox(projectPath: projectPath)
        let controllerByProjectPath = [projectPath: resolvedController]
        let sessionByProjectPath = [
            projectPath: OpenWorkspaceSessionState(
                projectPath: projectPath,
                controller: resolvedController
            ),
        ]
        self.state = state
        self.controllerByProjectPath = controllerByProjectPath
        self.sessionByProjectPath = sessionByProjectPath

        let baseDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("devhaven-attention-controller-\(UUID().uuidString)", isDirectory: true)
        self.attentionController = WorkspaceAttentionController(
            normalizePath: { $0 },
            openProjectPaths: { state.openProjectPaths },
            activeProjectPath: { state.activeProjectPath },
            notificationsEnabled: { state.notificationsEnabled },
            workspaceSession: { sessionByProjectPath[$0 ?? ""] },
            workspaceController: { controllerByProjectPath[$0] },
            resolvedPresentedTabSelection: { projectPath, controller in
                guard let resolvedController = controller ?? controllerByProjectPath[projectPath],
                      let selectedTabID = resolvedController.selectedTabId
                else {
                    return nil
                }
                return .terminal(selectedTabID)
            },
            isWorkspacePaneCurrentlyFocused: { projectPath, tabID, paneID in
                guard let controller = controllerByProjectPath[projectPath] else {
                    return false
                }
                return controller.selectedTabId == tabID && controller.selectedPane?.id == paneID
            },
            currentPaneIDForSignal: { signal in
                Self.currentPaneID(for: signal, controllerByProjectPath: controllerByProjectPath)
            },
            attentionStateByProjectPath: { state.attentionStatesByProjectPath },
            setAttentionStateByProjectPath: { state.attentionStatesByProjectPath = $0 },
            agentDisplayOverridesByProjectPath: { state.agentDisplayOverridesByProjectPath },
            setAgentDisplayOverridesByProjectPath: { state.agentDisplayOverridesByProjectPath = $0 },
            reportError: { state.reportedErrors.append($0) },
            codexDisplayCandidatesDidChange: { candidates in
                state.codexCandidates = candidates
                state.codexCandidateRevision += 1
            },
            agentSignalStore: WorkspaceAgentSignalStore(baseDirectoryURL: baseDirectoryURL)
        )
    }

    private static func currentPaneID(
        for signal: WorkspaceAgentSessionSignal,
        controllerByProjectPath: [String: GhosttyWorkspaceController]
    ) -> String? {
        guard let controller = controllerByProjectPath[signal.projectPath] else {
            return nil
        }
        for tab in controller.tabs {
            for pane in tab.leaves {
                if pane.items.contains(where: {
                    $0.id == signal.surfaceId || $0.request.terminalSessionId == signal.terminalSessionId
                }) {
                    return pane.id
                }
            }
        }
        return nil
    }
}
