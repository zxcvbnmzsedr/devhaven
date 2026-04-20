import Foundation

extension NativeAppViewModel {
    public func workspaceRunConsoleState(for projectPath: String) -> WorkspaceRunConsoleState? {
        workspaceRunController.consoleState(for: projectPath)
    }

    public func availableWorkspaceRunConfigurations(in projectPath: String? = nil) -> [WorkspaceRunConfiguration] {
        workspaceRunController.availableConfigurations(in: projectPath)
    }

    public func selectedWorkspaceRunConfiguration(in projectPath: String? = nil) -> WorkspaceRunConfiguration? {
        workspaceRunController.selectedConfiguration(in: projectPath)
    }

    public func workspaceRunToolbarState(for projectPath: String? = nil) -> WorkspaceRunToolbarState {
        workspaceRunController.toolbarState(for: projectPath)
    }

    public func selectWorkspaceRunConfiguration(_ configurationID: String, in projectPath: String? = nil) {
        workspaceRunController.selectConfiguration(configurationID, in: projectPath)
    }

    public func runSelectedWorkspaceConfiguration(in projectPath: String? = nil) throws {
        try workspaceRunController.runSelectedConfiguration(in: projectPath)
    }

    public func selectWorkspaceRunSession(_ sessionID: String, in projectPath: String? = nil) {
        workspaceRunController.selectSession(sessionID, in: projectPath)
    }

    public func stopSelectedWorkspaceRunSession(in projectPath: String? = nil) {
        workspaceRunController.stopSelectedSession(in: projectPath)
    }

    public func toggleWorkspaceRunConsole(in projectPath: String? = nil) {
        workspaceRunController.toggleConsole(in: projectPath)
    }

    public func updateWorkspaceRunConsolePanelHeight(_ height: Double, in projectPath: String? = nil) {
        workspaceRunController.updateConsolePanelHeight(height, in: projectPath)
    }

    public func clearSelectedWorkspaceRunConsoleBuffer(in projectPath: String? = nil) {
        workspaceRunController.clearSelectedConsoleBuffer(in: projectPath)
    }

    public func openSelectedWorkspaceRunLog(in projectPath: String? = nil) throws {
        try workspaceRunController.openSelectedLog(in: projectPath)
    }
}
