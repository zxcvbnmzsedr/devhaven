import SwiftUI
import DevHavenCore

struct WorkspaceRootView: View {
    @Bindable var viewModel: NativeAppViewModel
    let terminalStoreRegistry: WorkspaceTerminalStoreRegistry
    let cmuxHostStore: CmuxEmbeddedHostStore
    var body: some View {
        let projectNames = Dictionary(
            viewModel.openWorkspaceProjects.map { ($0.path, $0.name) },
            uniquingKeysWith: { first, _ in first }
        )
        let projects = viewModel.openWorkspaceSessions.map { session in
            CmuxEmbeddedProject(
                path: session.projectPath,
                name: session.isQuickTerminal
                    ? "快速终端"
                    : projectNames[session.projectPath]
                        ?? URL(fileURLWithPath: session.projectPath).lastPathComponent
            )
        }

        CmuxEmbeddedHostView(
            workingDirectory: viewModel.activeWorkspaceProjectPath,
            projects: projects,
            hostStore: cmuxHostStore
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .top)
    }
}
