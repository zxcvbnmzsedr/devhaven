import Foundation

@MainActor
final class WorkspaceRunController {
    private let runManager: any WorkspaceRunManaging
    private let terminalCommandRunner: @Sendable (String, [String]) throws -> Void
    private let normalizePath: @MainActor (String) -> String
    private let activeProjectPath: @MainActor () -> String?
    private let openProjectPaths: @MainActor () -> [String]
    private let workspaceSession: @MainActor (String) -> OpenWorkspaceSessionState?
    private let availableConfigurations: @MainActor (String) -> [WorkspaceRunConfiguration]
    private let reportError: @MainActor (String?) -> Void

    private var consoleStateByProjectPath: [String: WorkspaceRunConsoleState] = [:]

    init(
        runManager: any WorkspaceRunManaging,
        terminalCommandRunner: @escaping @Sendable (String, [String]) throws -> Void,
        normalizePath: @escaping @MainActor (String) -> String,
        activeProjectPath: @escaping @MainActor () -> String?,
        openProjectPaths: @escaping @MainActor () -> [String],
        workspaceSession: @escaping @MainActor (String) -> OpenWorkspaceSessionState?,
        availableConfigurations: @escaping @MainActor (String) -> [WorkspaceRunConfiguration],
        reportError: @escaping @MainActor (String?) -> Void
    ) {
        self.runManager = runManager
        self.terminalCommandRunner = terminalCommandRunner
        self.normalizePath = normalizePath
        self.activeProjectPath = activeProjectPath
        self.openProjectPaths = openProjectPaths
        self.workspaceSession = workspaceSession
        self.availableConfigurations = availableConfigurations
        self.reportError = reportError

        runManager.onEvent = { [weak self] event in
            self?.handleRunManagerEvent(event)
        }
    }

    func consoleState(for projectPath: String) -> WorkspaceRunConsoleState? {
        consoleStateByProjectPath[normalizePath(projectPath)]
    }

    func availableConfigurations(in projectPath: String? = nil) -> [WorkspaceRunConfiguration] {
        guard let resolvedProjectPath = resolveProjectPath(projectPath) else {
            return []
        }
        return availableConfigurations(resolvedProjectPath)
    }

    func selectedConfiguration(in projectPath: String? = nil) -> WorkspaceRunConfiguration? {
        guard let resolvedProjectPath = resolveProjectPath(projectPath) else {
            return nil
        }
        let configurations = availableConfigurations(resolvedProjectPath)
        guard !configurations.isEmpty else {
            return nil
        }

        let state = consoleStateByProjectPath[resolvedProjectPath] ?? WorkspaceRunConsoleState()
        if let selectedConfigurationID = state.selectedConfigurationID,
           let selected = configurations.first(where: { $0.id == selectedConfigurationID }) {
            return selected
        }
        return configurations.first
    }

    func toolbarState(for projectPath: String? = nil) -> WorkspaceRunToolbarState {
        guard let resolvedProjectPath = resolveProjectPath(projectPath) else {
            return WorkspaceRunToolbarState()
        }

        let configurations = availableConfigurations(resolvedProjectPath)
        let consoleState = consoleStateByProjectPath[resolvedProjectPath] ?? WorkspaceRunConsoleState()
        let selectedConfiguration = selectedConfiguration(in: resolvedProjectPath)

        return WorkspaceRunToolbarState(
            configurations: configurations,
            selectedConfigurationID: consoleState.selectedConfigurationID ?? selectedConfiguration?.id,
            canRun: selectedConfiguration?.canRun ?? false,
            canStop: consoleState.selectedSession?.state.isActive ?? false,
            hasSessions: !consoleState.sessions.isEmpty,
            isLogsVisible: consoleState.isVisible
        )
    }

    func selectConfiguration(_ configurationID: String, in projectPath: String? = nil) {
        guard let resolvedProjectPath = resolveProjectPath(projectPath) else {
            return
        }
        var state = consoleStateByProjectPath[resolvedProjectPath] ?? WorkspaceRunConsoleState()
        state.selectedConfigurationID = configurationID
        consoleStateByProjectPath[resolvedProjectPath] = state
    }

    func runSelectedConfiguration(in projectPath: String? = nil) throws {
        guard let resolvedProjectPath = resolveProjectPath(projectPath),
              let session = workspaceSession(resolvedProjectPath),
              let configuration = selectedConfiguration(in: resolvedProjectPath)
        else {
            let error = WorkspaceTerminalCommandError.noActiveWorkspace
            reportError(error.localizedDescription)
            throw error
        }

        guard configuration.canRun else {
            let message = configuration.disabledReason ?? "当前运行配置缺少必要参数，请先完成配置。"
            let error = NSError(
                domain: "DevHavenCore.WorkspaceRunConfiguration",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
            reportError(message)
            throw error
        }

        var state = consoleStateByProjectPath[resolvedProjectPath] ?? WorkspaceRunConsoleState()
        if let existingSession = state.sessions.first(where: { $0.configurationID == configuration.id }),
           existingSession.state.isActive {
            runManager.stop(sessionID: existingSession.id)
        }

        let sessionID = UUID().uuidString
        let placeholderSession = WorkspaceRunSession(
            id: sessionID,
            configurationID: configuration.id,
            configurationName: configuration.name,
            configurationSource: configuration.source,
            projectPath: resolvedProjectPath,
            rootProjectPath: session.rootProjectPath,
            command: configuration.displayCommand,
            workingDirectory: configuration.workingDirectory,
            state: .starting,
            startedAt: Date()
        )
        if let existingIndex = state.sessions.firstIndex(where: { $0.configurationID == configuration.id }) {
            state.sessions[existingIndex] = placeholderSession
        } else {
            state.sessions.append(placeholderSession)
        }
        state.selectedSessionID = sessionID
        state.selectedConfigurationID = configuration.id
        state.isVisible = true
        consoleStateByProjectPath[resolvedProjectPath] = state

        do {
            let runSession = try runManager.start(
                WorkspaceRunStartRequest(
                    sessionID: sessionID,
                    configurationID: configuration.id,
                    configurationName: configuration.name,
                    configurationSource: configuration.source,
                    projectPath: resolvedProjectPath,
                    rootProjectPath: session.rootProjectPath,
                    executable: configuration.executable,
                    displayCommand: configuration.displayCommand,
                    workingDirectory: configuration.workingDirectory
                )
            )
            var currentState = consoleStateByProjectPath[resolvedProjectPath] ?? state
            if let index = currentState.sessions.firstIndex(where: { $0.id == sessionID }) {
                var updatedSession = runSession
                updatedSession.startedAt = currentState.sessions[index].startedAt
                updatedSession.displayBuffer = currentState.sessions[index].displayBuffer
                currentState.sessions[index] = updatedSession
            } else if let index = currentState.sessions.firstIndex(where: { $0.configurationID == configuration.id }) {
                currentState.sessions[index] = runSession
            } else {
                currentState.sessions.append(runSession)
            }
            consoleStateByProjectPath[resolvedProjectPath] = currentState
            reportError(nil)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            let failureBuffer = "启动失败：\(message)\n"
            var currentState = consoleStateByProjectPath[resolvedProjectPath] ?? state
            let failureSession = WorkspaceRunSession(
                id: sessionID,
                configurationID: configuration.id,
                configurationName: configuration.name,
                configurationSource: configuration.source,
                projectPath: resolvedProjectPath,
                rootProjectPath: session.rootProjectPath,
                command: configuration.command,
                workingDirectory: configuration.workingDirectory,
                state: .failed(exitCode: -1),
                startedAt: currentState.sessions.first(where: { $0.id == sessionID })?.startedAt ?? Date(),
                endedAt: Date(),
                displayBuffer: failureBuffer
            )
            if let index = currentState.sessions.firstIndex(where: { $0.id == sessionID || $0.configurationID == configuration.id }) {
                currentState.sessions[index] = failureSession
            } else {
                currentState.sessions.append(failureSession)
            }
            consoleStateByProjectPath[resolvedProjectPath] = currentState
            reportError(message)
            throw error
        }
    }

    func selectSession(_ sessionID: String, in projectPath: String? = nil) {
        guard let resolvedProjectPath = resolveProjectPath(projectPath),
              var state = consoleStateByProjectPath[resolvedProjectPath],
              state.sessions.contains(where: { $0.id == sessionID })
        else {
            return
        }
        state.selectedSessionID = sessionID
        state.selectedConfigurationID = state.sessions.first(where: { $0.id == sessionID })?.configurationID
        state.isVisible = true
        consoleStateByProjectPath[resolvedProjectPath] = state
    }

    func stopSelectedSession(in projectPath: String? = nil) {
        guard let resolvedProjectPath = resolveProjectPath(projectPath),
              let state = consoleStateByProjectPath[resolvedProjectPath],
              let sessionID = state.selectedSession?.id
        else {
            return
        }
        runManager.stop(sessionID: sessionID)
    }

    func toggleConsole(in projectPath: String? = nil) {
        guard let resolvedProjectPath = resolveProjectPath(projectPath),
              var state = consoleStateByProjectPath[resolvedProjectPath]
        else {
            return
        }
        state.isVisible.toggle()
        consoleStateByProjectPath[resolvedProjectPath] = state
    }

    func updateConsolePanelHeight(_ height: Double, in projectPath: String? = nil) {
        guard let resolvedProjectPath = resolveProjectPath(projectPath),
              var state = consoleStateByProjectPath[resolvedProjectPath]
        else {
            return
        }
        state.panelHeight = height
        consoleStateByProjectPath[resolvedProjectPath] = state
    }

    func clearSelectedConsoleBuffer(in projectPath: String? = nil) {
        guard let resolvedProjectPath = resolveProjectPath(projectPath),
              var state = consoleStateByProjectPath[resolvedProjectPath],
              let selectedSessionID = state.selectedSession?.id,
              let index = state.sessions.firstIndex(where: { $0.id == selectedSessionID })
        else {
            return
        }
        state.sessions[index].displayBuffer = ""
        consoleStateByProjectPath[resolvedProjectPath] = state
    }

    func openSelectedLog(in projectPath: String? = nil) throws {
        guard let resolvedProjectPath = resolveProjectPath(projectPath),
              let state = consoleStateByProjectPath[resolvedProjectPath],
              let path = state.selectedSession?.logFilePath
        else {
            return
        }
        do {
            try terminalCommandRunner("/usr/bin/open", [path])
            reportError(nil)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            reportError(message)
            throw error
        }
    }

    func retainConsoleState(for openProjectPaths: [String]) {
        let openPathSet = Set(openProjectPaths.map(normalizePath))
        consoleStateByProjectPath = consoleStateByProjectPath.filter { openPathSet.contains($0.key) }
    }

    private func resolveProjectPath(_ projectPath: String?) -> String? {
        let candidate = (projectPath ?? activeProjectPath()).map(normalizePath)
        guard let candidate else {
            return nil
        }
        guard openProjectPaths().map(normalizePath).contains(candidate) else {
            return nil
        }
        return candidate
    }

    private func handleRunManagerEvent(_ event: WorkspaceRunManagerEvent) {
        switch event {
        case let .output(projectPath, sessionID, chunk):
            updateConsoleState(for: projectPath) { state in
                guard let index = state.sessions.firstIndex(where: { $0.id == sessionID }) else {
                    return
                }
                state.sessions[index].appendDisplayChunk(chunk)
            }
        case let .stateChanged(projectPath, sessionID, runState):
            updateConsoleState(for: projectPath) { state in
                guard let index = state.sessions.firstIndex(where: { $0.id == sessionID }) else {
                    return
                }
                state.sessions[index].state = runState
                if !runState.isActive {
                    state.sessions[index].endedAt = Date()
                }
            }
        }
    }

    private func updateConsoleState(
        for projectPath: String,
        mutate: (inout WorkspaceRunConsoleState) -> Void
    ) {
        let normalizedProjectPath = normalizePath(projectPath)
        guard var state = consoleStateByProjectPath[normalizedProjectPath] else {
            return
        }
        mutate(&state)
        consoleStateByProjectPath[normalizedProjectPath] = state
    }
}
