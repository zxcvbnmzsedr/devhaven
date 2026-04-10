import XCTest
@testable import DevHavenCore

final class WorkspaceCLICommandStoreTests: XCTestCase {
    func testWriteAndLoadServerRequestAndResponseRoundTrip() throws {
        let baseURL = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: baseURL) }

        let store = WorkspaceCLICommandStore(baseDirectoryURL: baseURL)
        let serverState = WorkspaceCLIServerState(pid: 1234, isReady: true, appVersion: "1.0.0", buildVersion: "10")
        try store.writeServerState(serverState)

        let request = WorkspaceCLIRequestEnvelope(
            requestID: "request-1",
            source: WorkspaceCLIRequestSource(
                pid: 999,
                currentWorkingDirectory: "/tmp",
                arguments: ["devhaven", "status", "--json"]
            ),
            command: WorkspaceCLICommandPayload(kind: .status)
        )
        let requestURL = try store.writeRequest(request)
        let queuedRequest = try XCTUnwrap(store.pendingRequests().first)

        XCTAssertEqual(queuedRequest.fileURL.lastPathComponent, requestURL.lastPathComponent)
        XCTAssertEqual(queuedRequest.envelope.requestID, "request-1")
        let loadedServerState = try XCTUnwrap(store.loadServerState())
        XCTAssertEqual(loadedServerState.pid, serverState.pid)
        XCTAssertEqual(loadedServerState.isReady, serverState.isReady)
        XCTAssertEqual(loadedServerState.appVersion, serverState.appVersion)
        XCTAssertEqual(loadedServerState.buildVersion, serverState.buildVersion)
        XCTAssertEqual(loadedServerState.commands, serverState.commands)
        XCTAssertEqual(loadedServerState.namespaces, serverState.namespaces)

        let response = WorkspaceCLIResponseEnvelope(
            requestID: request.requestID,
            status: .succeeded,
            payload: WorkspaceCLIResponsePayload(status: .offline(), workspaces: [])
        )
        try store.writeResponse(response)
        let loadedResponse = try XCTUnwrap(store.loadResponse(requestID: request.requestID))
        XCTAssertEqual(loadedResponse.requestID, response.requestID)
        XCTAssertEqual(loadedResponse.status, response.status)
        XCTAssertEqual(loadedResponse.code, response.code)
        XCTAssertEqual(loadedResponse.message, response.message)
        XCTAssertEqual(loadedResponse.payload, response.payload)
    }

    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "DevHaven-WorkspaceCLICommandStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
