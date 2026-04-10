import XCTest
@testable import DevHavenCore

@MainActor
final class WorkspaceCLICommandCoordinatorTests: XCTestCase {
    func testCoordinatorProcessesRequestWrittenToRequestsDirectory() async throws {
        let baseURL = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: baseURL) }

        let store = WorkspaceCLICommandStore(baseDirectoryURL: baseURL)
        let viewModel = NativeAppViewModel()
        let coordinator = WorkspaceCLICommandCoordinator(
            viewModel: viewModel,
            store: store,
            responseRetentionInterval: 60
        )
        try coordinator.start()
        defer { coordinator.stop() }

        let request = WorkspaceCLIRequestEnvelope(
            requestID: "request-status",
            source: WorkspaceCLIRequestSource(
                pid: 1,
                currentWorkingDirectory: "/tmp",
                arguments: ["devhaven", "status", "--json"]
            ),
            command: WorkspaceCLICommandPayload(kind: .status)
        )

        try store.writeRequest(request)

        let response = try await waitForResponse(
            requestID: request.requestID,
            in: store,
            timeout: 2
        )

        XCTAssertEqual(response.status, .succeeded)
        XCTAssertEqual(response.payload?.status?.isRunning, true)
    }

    private func waitForResponse(
        requestID: String,
        in store: WorkspaceCLICommandStore,
        timeout: TimeInterval
    ) async throws -> WorkspaceCLIResponseEnvelope {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let response = try store.loadResponse(requestID: requestID) {
                return response
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("等待 CLI response 超时")
        throw CancellationError()
    }

    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "DevHaven-WorkspaceCLICommandCoordinatorTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
