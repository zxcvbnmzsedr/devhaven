import XCTest
@testable import DevHavenCore

@MainActor
final class WorkspaceRunManagerTests: XCTestCase {
    func testResolveLaunchDescriptorUsesResolvedUserShell() {
        let descriptor = WorkspaceRunManager.resolveLaunchDescriptor(
            for: .shell(command: "echo hello"),
            environment: ["SHELL": "/bin/bash"]
        )

        XCTAssertEqual(descriptor.program, "/bin/bash")
        XCTAssertEqual(descriptor.arguments, ["-i", "-l", "-c", "echo hello"])
    }

    func testStartPassesResolvedEnvironmentIntoProcess() async throws {
        let baseURL = FileManager.default.temporaryDirectory
            .appending(path: "DevHaven-WorkspaceRunManagerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        let logStore = WorkspaceRunLogStore(baseDirectoryURL: baseURL)
        let manager = WorkspaceRunManager(
            logStore: logStore,
            environmentResolver: { request, processEnvironment in
                var environment = WorkspaceRunManager.defaultEnvironment(
                    for: request,
                    processEnvironment: processEnvironment
                )
                environment["WORKSPACE_RUN_MANAGER_TEST"] = "ghostty-env"
                return environment
            }
        )

        let finished = expectation(description: "run-finished")
        var output = ""
        manager.onEvent = { event in
            switch event {
            case let .output(_, _, chunk):
                output.append(chunk)
            case let .stateChanged(_, _, state):
                switch state {
                case .completed, .failed, .stopped:
                    finished.fulfill()
                default:
                    break
                }
            }
        }

        _ = try manager.start(
            WorkspaceRunStartRequest(
                sessionID: UUID().uuidString,
                configurationID: "config",
                configurationName: "Env",
                configurationSource: .projectRunConfiguration,
                projectPath: baseURL.path,
                rootProjectPath: baseURL.path,
                executable: .process(program: "/usr/bin/env", arguments: []),
                displayCommand: "/usr/bin/env",
                workingDirectory: baseURL.path
            )
        )

        await fulfillment(of: [finished], timeout: 5)

        XCTAssertTrue(output.contains("WORKSPACE_RUN_MANAGER_TEST=ghostty-env"))
        XCTAssertTrue(output.contains("DEVHAVEN_PROJECT_PATH=\(baseURL.path)"))
        XCTAssertTrue(output.contains("TERM=xterm-256color"))
    }
}
