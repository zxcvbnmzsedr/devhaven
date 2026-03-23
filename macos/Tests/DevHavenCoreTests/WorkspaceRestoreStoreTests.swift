import XCTest
@testable import DevHavenCore

final class WorkspaceRestoreStoreTests: XCTestCase {
    func testSaveAndLoadSnapshotRoundTripWithPaneTextStoredSeparately() throws {
        let homeURL = try makeTemporaryHomeDirectory()
        defer { try? FileManager.default.removeItem(at: homeURL) }
        let store = WorkspaceRestoreStore(homeDirectoryURL: homeURL)
        let snapshot = makeSnapshot()

        try store.saveSnapshot(snapshot)
        let loaded = try XCTUnwrap(store.loadSnapshot())

        XCTAssertEqual(loaded.version, WorkspaceRestoreSnapshot.currentVersion)
        XCTAssertEqual(loaded.activeProjectPath, "/tmp/devhaven")
        let pane = try XCTUnwrap(loaded.sessions.first?.tabs.first?.tree.rootLeaf)
        XCTAssertNotNil(pane.snapshotTextRef)
        XCTAssertNil(pane.snapshotText, "pane 文本不应直接内联进 manifest")

        let paneText = try XCTUnwrap(store.loadPaneText(for: pane.snapshotTextRef))
        XCTAssertEqual(paneText, "pwd\n/tmp/devhaven")
    }

    func testLoadFallsBackToPreviousManifestWhenPrimaryManifestIsCorrupted() throws {
        let homeURL = try makeTemporaryHomeDirectory()
        defer { try? FileManager.default.removeItem(at: homeURL) }
        let store = WorkspaceRestoreStore(homeDirectoryURL: homeURL)
        let first = makeSnapshot(activeProjectPath: "/tmp/alpha")
        let second = makeSnapshot(activeProjectPath: "/tmp/beta")

        try store.saveSnapshot(first)
        try store.saveSnapshot(second)

        let manifestURL = homeURL
            .appending(path: ".devhaven", directoryHint: .isDirectory)
            .appending(path: "session-restore", directoryHint: .isDirectory)
            .appending(path: "manifest.json")
        try "{not-json".write(to: manifestURL, atomically: true, encoding: .utf8)

        let loaded = try XCTUnwrap(store.loadSnapshot())
        XCTAssertEqual(loaded.activeProjectPath, "/tmp/alpha")
    }

    func testLoadFallsBackToPreviousManifestWhenPaneIDChangesAndPreviousPaneTextMustStillExist() throws {
        let homeURL = try makeTemporaryHomeDirectory()
        defer { try? FileManager.default.removeItem(at: homeURL) }
        let store = WorkspaceRestoreStore(homeDirectoryURL: homeURL)
        let first = makeSnapshot(
            activeProjectPath: "/tmp/alpha",
            paneID: "workspace:test/pane:1",
            snapshotText: "first output"
        )
        let second = makeSnapshot(
            activeProjectPath: "/tmp/beta",
            paneID: "workspace:test/pane:2",
            snapshotText: "second output"
        )

        try store.saveSnapshot(first)
        try store.saveSnapshot(second)
        try corruptPrimaryManifest(in: homeURL)

        let loaded = try XCTUnwrap(store.loadSnapshot())
        let pane = try XCTUnwrap(loaded.sessions.first?.tabs.first?.tree.rootLeaf)
        XCTAssertEqual(loaded.activeProjectPath, "/tmp/alpha")
        XCTAssertEqual(store.loadPaneText(for: pane.snapshotTextRef), "first output")
    }

    func testLoadFallsBackToPreviousManifestWhenPaneIDIsReusedAndPreviousPaneTextMustStillExist() throws {
        let homeURL = try makeTemporaryHomeDirectory()
        defer { try? FileManager.default.removeItem(at: homeURL) }
        let store = WorkspaceRestoreStore(homeDirectoryURL: homeURL)
        let first = makeSnapshot(
            activeProjectPath: "/tmp/alpha",
            paneID: "workspace:test/pane:1",
            snapshotText: "first output"
        )
        let second = makeSnapshot(
            activeProjectPath: "/tmp/beta",
            paneID: "workspace:test/pane:1",
            snapshotText: "second output"
        )

        try store.saveSnapshot(first)
        try store.saveSnapshot(second)
        try corruptPrimaryManifest(in: homeURL)

        let loaded = try XCTUnwrap(store.loadSnapshot())
        let pane = try XCTUnwrap(loaded.sessions.first?.tabs.first?.tree.rootLeaf)
        XCTAssertEqual(loaded.activeProjectPath, "/tmp/alpha")
        XCTAssertEqual(store.loadPaneText(for: pane.snapshotTextRef), "first output")
    }

    func testFailedPrimaryManifestWriteDoesNotCorruptExistingSnapshotOrPaneText() throws {
        let homeURL = try makeTemporaryHomeDirectory()
        defer { try? FileManager.default.removeItem(at: homeURL) }

        var primaryManifestWriteCount = 0
        let store = WorkspaceRestoreStore(
            homeDirectoryURL: homeURL,
            manifestWriter: { data, url in
                if url.lastPathComponent == "manifest.json" {
                    primaryManifestWriteCount += 1
                    if primaryManifestWriteCount == 2 {
                        throw WorkspaceRestoreStoreTestsError.injectedManifestWriteFailure
                    }
                }
                try data.write(to: url, options: .atomic)
            }
        )

        let first = makeSnapshot(
            activeProjectPath: "/tmp/alpha",
            paneID: "workspace:test/pane:1",
            snapshotText: "first output"
        )
        let second = makeSnapshot(
            activeProjectPath: "/tmp/beta",
            paneID: "workspace:test/pane:2",
            snapshotText: "second output"
        )

        try store.saveSnapshot(first)
        XCTAssertThrowsError(try store.saveSnapshot(second))

        let loaded = try XCTUnwrap(store.loadSnapshot())
        let pane = try XCTUnwrap(loaded.sessions.first?.tabs.first?.tree.rootLeaf)
        XCTAssertEqual(loaded.activeProjectPath, "/tmp/alpha")
        XCTAssertEqual(store.loadPaneText(for: pane.snapshotTextRef), "first output")
    }

    func testLoadRejectsUnsupportedSnapshotVersionWithoutFallback() throws {
        let homeURL = try makeTemporaryHomeDirectory()
        defer { try? FileManager.default.removeItem(at: homeURL) }
        let store = WorkspaceRestoreStore(homeDirectoryURL: homeURL)
        var snapshot = makeSnapshot()
        snapshot.version = WorkspaceRestoreSnapshot.currentVersion + 1

        try store.saveSnapshot(snapshot)

        XCTAssertNil(store.loadSnapshot())
    }

    func testRemoveSnapshotDeletesManifestAndPaneTextFiles() throws {
        let homeURL = try makeTemporaryHomeDirectory()
        defer { try? FileManager.default.removeItem(at: homeURL) }
        let store = WorkspaceRestoreStore(homeDirectoryURL: homeURL)
        let snapshot = makeSnapshot()
        try store.saveSnapshot(snapshot)

        try store.removeSnapshot()

        XCTAssertNil(store.loadSnapshot())
        let paneRef = try XCTUnwrap(snapshot.sessions.first?.tabs.first?.tree.rootLeaf?.snapshotTextRef)
        XCTAssertNil(store.loadPaneText(for: paneRef))
    }

    private func makeSnapshot(
        activeProjectPath: String = "/tmp/devhaven",
        paneID: String = "workspace:test/pane:1",
        snapshotText: String = "pwd\n/tmp/devhaven"
    ) -> WorkspaceRestoreSnapshot {
        let paneRef = WorkspacePaneSnapshotTextRef.forPaneID(paneID)
        let pane = WorkspacePaneRestoreSnapshot(
            paneId: paneID,
            surfaceId: paneID.replacingOccurrences(of: "/pane:", with: "/surface:"),
            terminalSessionId: paneID.replacingOccurrences(of: "/pane:", with: "/session:"),
            restoredWorkingDirectory: "/tmp/devhaven",
            restoredTitle: "终端1",
            agentSummary: "Claude 正在等待",
            snapshotTextRef: paneRef,
            snapshotText: snapshotText
        )
        let tab = WorkspaceTabRestoreSnapshot(
            id: "workspace:test/tab:1",
            title: "终端1",
            focusedPaneId: pane.paneId,
            tree: WorkspacePaneTreeRestoreSnapshot(
                root: .leaf(pane),
                zoomedPaneId: nil
            )
        )
        let session = ProjectWorkspaceRestoreSnapshot(
            projectPath: "/tmp/devhaven",
            rootProjectPath: "/tmp/devhaven",
            isQuickTerminal: false,
            workspaceId: "workspace:test",
            selectedTabId: tab.id,
            nextTabNumber: 2,
            nextPaneNumber: 2,
            tabs: [tab]
        )
        return WorkspaceRestoreSnapshot(
            version: WorkspaceRestoreSnapshot.currentVersion,
            savedAt: Date(timeIntervalSince1970: 1_742_689_600),
            activeProjectPath: activeProjectPath,
            selectedProjectPath: activeProjectPath,
            sessions: [session]
        )
    }

    private func makeTemporaryHomeDirectory() throws -> URL {
        let homeURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
        return homeURL
    }

    private func corruptPrimaryManifest(in homeURL: URL) throws {
        let manifestURL = homeURL
            .appending(path: ".devhaven", directoryHint: .isDirectory)
            .appending(path: "session-restore", directoryHint: .isDirectory)
            .appending(path: "manifest.json")
        try "{not-json".write(to: manifestURL, atomically: true, encoding: .utf8)
    }
}

private enum WorkspaceRestoreStoreTestsError: Error {
    case injectedManifestWriteFailure
}

private extension WorkspacePaneTreeRestoreSnapshot {
    var rootLeaf: WorkspacePaneRestoreSnapshot? {
        guard case let .leaf(pane) = root else {
            return nil
        }
        return pane
    }
}
