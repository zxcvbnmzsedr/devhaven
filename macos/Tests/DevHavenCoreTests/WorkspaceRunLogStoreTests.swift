import XCTest
@testable import DevHavenCore

final class WorkspaceRunLogStoreTests: XCTestCase {
    func testAppendAndCloseLogFileKeepsContentAcrossReopen() throws {
        let baseURL = FileManager.default.temporaryDirectory
            .appending(path: "DevHaven-WorkspaceRunLogStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: baseURL) }

        let store = WorkspaceRunLogStore(baseDirectoryURL: baseURL)
        let logFileURL = try store.createLogFile(scriptName: "demo", sessionID: "session")

        try store.append("hello\n", to: logFileURL)
        try store.append("world\n", to: logFileURL)
        store.closeLogFile(at: logFileURL)
        try store.append("tail\n", to: logFileURL)
        store.closeLogFile(at: logFileURL)

        let content = try String(contentsOf: logFileURL, encoding: .utf8)
        XCTAssertEqual(content, "hello\nworld\ntail\n")
    }
}
