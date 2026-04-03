import Foundation
import XCTest
@testable import DevHavenCore

@MainActor
final class WorkspaceRestoreCoordinatorTests: XCTestCase {
    func testFlushNowSkipsPersistingEquivalentSnapshot() throws {
        let tempHomeURL = makeTemporaryHomeDirectory()
        defer { try? FileManager.default.removeItem(at: tempHomeURL) }

        let manifestWriteCounter = AtomicCounter()
        let store = WorkspaceRestoreStore(
            homeDirectoryURL: tempHomeURL,
            manifestWriter: { data, url in
                manifestWriteCounter.increment()
                try data.write(to: url, options: .atomic)
            }
        )
        let coordinator = WorkspaceRestoreCoordinator(store: store, autosaveDelayNanoseconds: 0)
        let projectPath = "/tmp/devhaven-restore"
        let session = OpenWorkspaceSessionState(
            projectPath: projectPath,
            controller: GhosttyWorkspaceController(projectPath: projectPath)
        )

        try coordinator.flushNow(
            activeProjectPath: projectPath,
            selectedProjectPath: projectPath,
            sessions: [session],
            paneSnapshotProvider: { _, _ in
                WorkspaceTerminalRestoreContext(
                    workingDirectory: projectPath,
                    title: "Shell",
                    snapshotText: "echo first",
                    agentSummary: nil
                )
            },
            editorRestoreProvider: nil
        )

        let writesAfterFirstFlush = manifestWriteCounter.value
        XCTAssertGreaterThan(writesAfterFirstFlush, 0)

        try coordinator.flushNow(
            activeProjectPath: projectPath,
            selectedProjectPath: projectPath,
            sessions: [session],
            paneSnapshotProvider: { _, _ in
                WorkspaceTerminalRestoreContext(
                    workingDirectory: projectPath,
                    title: "Shell",
                    snapshotText: "echo first",
                    agentSummary: nil
                )
            },
            editorRestoreProvider: nil
        )

        XCTAssertEqual(manifestWriteCounter.value, writesAfterFirstFlush)
    }

    func testSaveAutosaveSnapshotDropsStaleGeneration() throws {
        let tempHomeURL = makeTemporaryHomeDirectory()
        defer { try? FileManager.default.removeItem(at: tempHomeURL) }

        let store = WorkspaceRestoreStore(homeDirectoryURL: tempHomeURL)
        let newerSnapshot = Self.makeRestoreSnapshot(
            projectPath: "/tmp/newer",
            snapshotText: "echo newer"
        )
        let staleSnapshot = Self.makeRestoreSnapshot(
            projectPath: "/tmp/stale",
            snapshotText: "echo stale"
        )

        let persistedNewer = try store.saveAutosaveSnapshot(newerSnapshot, generation: 2)
        let persistedStale = try store.saveAutosaveSnapshot(staleSnapshot, generation: 1)

        XCTAssertNotNil(persistedNewer)
        XCTAssertNil(persistedStale)

        let loadedSnapshot = try XCTUnwrap(store.loadSnapshot())
        XCTAssertEqual(loadedSnapshot.activeProjectPath, "/tmp/newer")
        let paneRef = try XCTUnwrap(loadedSnapshot.sessions.first?.tabs.first?.tree.leaves.first?.snapshotTextRef)
        XCTAssertEqual(store.loadPaneText(for: paneRef), "echo newer")
    }

    private func makeTemporaryHomeDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private nonisolated static func makeRestoreSnapshot(
        projectPath: String,
        snapshotText: String
    ) -> WorkspaceRestoreSnapshot {
        WorkspaceRestoreSnapshot(
            activeProjectPath: projectPath,
            selectedProjectPath: projectPath,
            sessions: [
                ProjectWorkspaceRestoreSnapshot(
                    projectPath: projectPath,
                    rootProjectPath: projectPath,
                    isQuickTerminal: false,
                    workspaceId: "workspace-1",
                    selectedTabId: "tab-1",
                    nextTabNumber: 2,
                    nextPaneNumber: 2,
                    tabs: [
                        WorkspaceTabRestoreSnapshot(
                            id: "tab-1",
                            title: "Tab 1",
                            focusedPaneId: "pane-1",
                            tree: WorkspacePaneTreeRestoreSnapshot(
                                root: .leaf(
                                    WorkspacePaneRestoreSnapshot(
                                        paneId: "pane-1",
                                        selectedItemId: "surface-1",
                                        items: [
                                            WorkspacePaneItemRestoreSnapshot(
                                                surfaceId: "surface-1",
                                                terminalSessionId: "terminal-1",
                                                restoredWorkingDirectory: projectPath,
                                                restoredTitle: "Shell",
                                                agentSummary: nil,
                                                snapshotTextRef: nil,
                                                snapshotText: snapshotText
                                            )
                                        ]
                                    )
                                ),
                                zoomedPaneId: nil
                            )
                        )
                    ]
                )
            ]
        )
    }
}

private final class AtomicCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    func increment() {
        lock.lock()
        storage += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
