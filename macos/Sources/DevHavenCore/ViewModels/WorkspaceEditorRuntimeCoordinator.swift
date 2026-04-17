import Foundation

protocol WorkspaceEditorDirectoryWatching: AnyObject {
    func stop()
}

@MainActor
final class WorkspaceEditorRuntimeCoordinator {
    private let editorTabsForProject: @MainActor (String) -> [WorkspaceEditorTabState]
    private let parentDirectoryPath: @MainActor (String) -> String
    private let normalizePath: @MainActor (String) -> String
    private let runtimeSessionsForProject: @MainActor (String) -> [String: WorkspaceEditorRuntimeSessionState]
    private let setRuntimeSessions: @MainActor (String, [String: WorkspaceEditorRuntimeSessionState]) -> Void
    private let createWatcher: @MainActor (String, @escaping @Sendable () -> Void) -> (any WorkspaceEditorDirectoryWatching)?
    private let handleTabsChangedInDirectory: @MainActor ([String], String) -> Void
    private var watchersByProjectPath: [String: [String: any WorkspaceEditorDirectoryWatching]] = [:]

    init(
        editorTabsForProject: @escaping @MainActor (String) -> [WorkspaceEditorTabState],
        parentDirectoryPath: @escaping @MainActor (String) -> String,
        normalizePath: @escaping @MainActor (String) -> String,
        runtimeSessionsForProject: @escaping @MainActor (String) -> [String: WorkspaceEditorRuntimeSessionState],
        setRuntimeSessions: @escaping @MainActor (String, [String: WorkspaceEditorRuntimeSessionState]) -> Void,
        createWatcher: @escaping @MainActor (String, @escaping @Sendable () -> Void) -> (any WorkspaceEditorDirectoryWatching)?,
        handleTabsChangedInDirectory: @escaping @MainActor ([String], String) -> Void
    ) {
        self.editorTabsForProject = editorTabsForProject
        self.parentDirectoryPath = parentDirectoryPath
        self.normalizePath = normalizePath
        self.runtimeSessionsForProject = runtimeSessionsForProject
        self.setRuntimeSessions = setRuntimeSessions
        self.createWatcher = createWatcher
        self.handleTabsChangedInDirectory = handleTabsChangedInDirectory
    }

    func updateRuntimeSession(
        _ session: WorkspaceEditorRuntimeSessionState,
        tabID: String,
        in projectPath: String
    ) {
        guard editorTabsForProject(projectPath).contains(where: { $0.id == tabID }) else {
            return
        }

        var sessions = runtimeSessionsForProject(projectPath)
        if session == WorkspaceEditorRuntimeSessionState() {
            sessions.removeValue(forKey: tabID)
        } else {
            sessions[tabID] = session
        }
        setRuntimeSessions(projectPath, sessions)
    }

    func resetRuntimeSession(_ tabID: String, in projectPath: String) {
        var sessions = runtimeSessionsForProject(projectPath)
        sessions.removeValue(forKey: tabID)
        setRuntimeSessions(projectPath, sessions)
    }

    func removeRuntimeSession(_ tabID: String, in projectPath: String) {
        resetRuntimeSession(tabID, in: projectPath)
    }

    func syncRuntimeSessions(for projectPath: String) {
        let validTabIDs = Set(editorTabsForProject(projectPath).map(\.id))
        guard !validTabIDs.isEmpty else {
            setRuntimeSessions(projectPath, [:])
            return
        }

        let sessions = runtimeSessionsForProject(projectPath).filter { validTabIDs.contains($0.key) }
        setRuntimeSessions(projectPath, sessions)
    }

    func syncDirectoryWatchers(for projectPath: String) {
        let requiredDirectories = Set(editorTabsForProject(projectPath).map {
            parentDirectoryPath($0.filePath)
        })
        var watchers = watchersByProjectPath[projectPath] ?? [:]

        for directoryPath in Set(watchers.keys).subtracting(requiredDirectories) {
            watchers.removeValue(forKey: directoryPath)?.stop()
        }

        for directoryPath in requiredDirectories {
            let normalizedDirectoryPath = normalizePath(directoryPath)
            guard watchers[normalizedDirectoryPath] == nil else {
                continue
            }
            let watcher = createWatcher(normalizedDirectoryPath) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.handleDirectoryEvent(normalizedDirectoryPath, projectPath: projectPath)
                }
            }
            if let watcher {
                watchers[normalizedDirectoryPath] = watcher
            }
        }

        watchersByProjectPath[projectPath] = watchers
    }

    func clearProjectState(_ projectPath: String) {
        watchersByProjectPath[projectPath]?.values.forEach { $0.stop() }
        watchersByProjectPath[projectPath] = nil
        setRuntimeSessions(projectPath, [:])
    }

    func removeProjectState(_ projectPath: String) {
        watchersByProjectPath[projectPath]?.values.forEach { $0.stop() }
        watchersByProjectPath[projectPath] = nil
        setRuntimeSessions(projectPath, [:])
    }

    private func handleDirectoryEvent(_ directoryPath: String, projectPath: String) {
        let normalizedDirectoryPath = normalizePath(directoryPath)
        let tabIDs = editorTabsForProject(projectPath)
            .filter { parentDirectoryPath($0.filePath) == normalizedDirectoryPath }
            .map(\.id)
        guard !tabIDs.isEmpty else {
            syncDirectoryWatchers(for: projectPath)
            return
        }
        handleTabsChangedInDirectory(tabIDs, projectPath)
    }
}
