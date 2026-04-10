import XCTest
@testable import DevHavenCore

@MainActor
final class WorkspaceCLICommandExecutorTests: XCTestCase {
    func testWorkspaceCloseProjectClosesCurrentSession() {
        let projectPath = "/tmp/devhaven-cli-project"
        let viewModel = NativeAppViewModel()
        viewModel.openWorkspaceSessions = [
            OpenWorkspaceSessionState(
                projectPath: projectPath,
                controller: GhosttyWorkspaceController(projectPath: projectPath)
            )
        ]
        viewModel.activeWorkspaceProjectPath = projectPath

        let executor = WorkspaceCLICommandExecutor(viewModel: viewModel)
        let response = executor.execute(
            WorkspaceCLIRequestEnvelope(
                requestID: "request-close-project",
                source: WorkspaceCLIRequestSource(
                    pid: 1,
                    currentWorkingDirectory: "/tmp",
                    arguments: ["devhaven", "workspace", "close", "--current", "--scope", "project", "--json"]
                ),
                command: WorkspaceCLICommandPayload(
                    kind: .workspaceClose,
                    target: WorkspaceCLICommandTarget(projectPath: projectPath, useCurrentContext: true),
                    closeScope: .project
                )
            )
        )

        XCTAssertEqual(response.status, .succeeded)
        XCTAssertTrue(viewModel.openWorkspaceSessions.isEmpty)
        XCTAssertNil(viewModel.activeWorkspaceProjectPath)
    }

    func testCapabilitiesIncludesPhaseOneCommands() {
        let viewModel = NativeAppViewModel()
        let executor = WorkspaceCLICommandExecutor(viewModel: viewModel)

        let response = executor.execute(
            WorkspaceCLIRequestEnvelope(
                requestID: "request-capabilities",
                source: WorkspaceCLIRequestSource(
                    pid: 1,
                    currentWorkingDirectory: "/tmp",
                    arguments: ["devhaven", "capabilities", "--json"]
                ),
                command: WorkspaceCLICommandPayload(kind: .capabilities)
            )
        )

        let capabilities = response.payload?.capabilities
        XCTAssertEqual(response.status, .succeeded)
        XCTAssertTrue(capabilities?.commands.contains("workspace.close") == true)
        XCTAssertTrue(capabilities?.commands.contains("tool-window.toggle") == true)
    }
}
