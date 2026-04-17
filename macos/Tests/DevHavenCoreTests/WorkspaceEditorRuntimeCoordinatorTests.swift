import XCTest
@testable import DevHavenCore

@MainActor
final class WorkspaceEditorRuntimeCoordinatorTests: XCTestCase {
    func testUpdateAndSyncRuntimeSessionsTrimStaleEntries() {
        let harness = WorkspaceEditorRuntimeCoordinatorHarness()
        let tab = harness.makeTab(id: "editor-1", filePath: "/tmp/devhaven/A.swift")
        harness.tabsByProjectPath[harness.projectPath] = [tab]

        let session = WorkspaceEditorRuntimeSessionState(
            markdownPresentationMode: .preview,
            markdownSplitRatio: 0.7
        )
        harness.coordinator.updateRuntimeSession(session, tabID: tab.id, in: harness.projectPath)
        XCTAssertEqual(harness.runtimeSessionsByProjectPath[harness.projectPath]?[tab.id], session)

        harness.tabsByProjectPath[harness.projectPath] = []
        harness.coordinator.syncRuntimeSessions(for: harness.projectPath)
        XCTAssertEqual(harness.runtimeSessionsByProjectPath[harness.projectPath], [:])
    }

    func testSyncDirectoryWatchersAddsRemovesAndClearsProjectState() {
        let harness = WorkspaceEditorRuntimeCoordinatorHarness()
        harness.tabsByProjectPath[harness.projectPath] = [
            harness.makeTab(id: "editor-1", filePath: "/tmp/devhaven/A.swift"),
            harness.makeTab(id: "editor-2", filePath: "/tmp/devhaven/sub/B.swift"),
        ]

        harness.coordinator.syncDirectoryWatchers(for: harness.projectPath)
        XCTAssertEqual(Set(harness.createdWatchers.keys), Set(["/tmp/devhaven", "/tmp/devhaven/sub"]))

        harness.tabsByProjectPath[harness.projectPath] = [
            harness.makeTab(id: "editor-2", filePath: "/tmp/devhaven/sub/B.swift"),
        ]
        harness.coordinator.syncDirectoryWatchers(for: harness.projectPath)
        XCTAssertTrue(harness.createdWatchers["/tmp/devhaven"]?.didStop == true)
        XCTAssertFalse(harness.createdWatchers["/tmp/devhaven/sub"]?.didStop == true)

        harness.coordinator.clearProjectState(harness.projectPath)
        XCTAssertTrue(harness.createdWatchers["/tmp/devhaven/sub"]?.didStop == true)
        XCTAssertEqual(harness.runtimeSessionsByProjectPath[harness.projectPath], [:])
    }

    func testWatcherEventDispatchesTabIDsAndResyncsWhenDirectoryBecomesUnused() {
        let harness = WorkspaceEditorRuntimeCoordinatorHarness()
        let tab = harness.makeTab(id: "editor-1", filePath: "/tmp/devhaven/A.swift")
        harness.tabsByProjectPath[harness.projectPath] = [tab]
        harness.coordinator.syncDirectoryWatchers(for: harness.projectPath)

        harness.createdWatchers["/tmp/devhaven"]?.fire()
        XCTAssertTrue(waitUntil(timeout: 1.0) { harness.directoryEvents.count == 1 })
        XCTAssertEqual(harness.directoryEvents.first?.0, [tab.id])
        XCTAssertEqual(harness.directoryEvents.first?.1, harness.projectPath)

        harness.directoryEvents = []
        harness.tabsByProjectPath[harness.projectPath] = []
        harness.createdWatchers["/tmp/devhaven"]?.fire()
        XCTAssertTrue(waitUntil(timeout: 1.0) { harness.createdWatchers["/tmp/devhaven"]?.didStop == true })
        XCTAssertTrue(harness.directoryEvents.isEmpty)
    }

    @MainActor
    @discardableResult
    private func waitUntil(
        timeout: TimeInterval,
        condition: @escaping @MainActor () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        return condition()
    }
}

@MainActor
private final class WorkspaceEditorRuntimeCoordinatorHarness {
    let projectPath = "/tmp/devhaven-project"
    var tabsByProjectPath: [String: [WorkspaceEditorTabState]] = [:]
    var runtimeSessionsByProjectPath: [String: [String: WorkspaceEditorRuntimeSessionState]] = [:]
    var createdWatchers: [String: FakeWorkspaceEditorDirectoryWatcher] = [:]
    var directoryEvents: [([String], String)] = []

    lazy var coordinator = WorkspaceEditorRuntimeCoordinator(
        editorTabsForProject: { [unowned self] in tabsByProjectPath[$0] ?? [] },
        parentDirectoryPath: { filePath in
            URL(fileURLWithPath: filePath).deletingLastPathComponent().path
        },
        normalizePath: { $0 },
        runtimeSessionsForProject: { [unowned self] in runtimeSessionsByProjectPath[$0] ?? [:] },
        setRuntimeSessions: { [unowned self] projectPath, sessions in
            runtimeSessionsByProjectPath[projectPath] = sessions
        },
        createWatcher: { [unowned self] directoryPath, callback in
            let watcher = FakeWorkspaceEditorDirectoryWatcher(onEvent: callback)
            createdWatchers[directoryPath] = watcher
            return watcher
        },
        handleTabsChangedInDirectory: { [unowned self] tabIDs, projectPath in
            directoryEvents.append((tabIDs, projectPath))
        }
    )

    func makeTab(id: String, filePath: String) -> WorkspaceEditorTabState {
        WorkspaceEditorTabState(
            id: id,
            identity: filePath,
            projectPath: projectPath,
            filePath: filePath,
            title: URL(fileURLWithPath: filePath).lastPathComponent,
            kind: .text,
            text: "",
            isEditable: true
        )
    }
}

private final class FakeWorkspaceEditorDirectoryWatcher: WorkspaceEditorDirectoryWatching {
    private let onEvent: @Sendable () -> Void
    private(set) var didStop = false

    init(onEvent: @escaping @Sendable () -> Void) {
        self.onEvent = onEvent
    }

    func fire() {
        onEvent()
    }

    func stop() {
        didStop = true
    }
}
