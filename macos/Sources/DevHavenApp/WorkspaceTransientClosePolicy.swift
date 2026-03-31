import DevHavenCore

enum WorkspaceTransientTerminalCloseAction {
    case tab
}

struct WorkspaceTransientClosePolicy {
    static func shouldCloseWorkspace(
        for action: WorkspaceTransientTerminalCloseAction,
        project: Project,
        terminalTabCount: Int,
        hasEditorTabs: Bool,
        hasDiffTabs: Bool
    ) -> Bool {
        guard project.isTransientWorkspaceProject,
              !hasEditorTabs,
              !hasDiffTabs
        else {
            return false
        }

        switch action {
        case .tab:
            return terminalTabCount == 1
        }
    }
}
