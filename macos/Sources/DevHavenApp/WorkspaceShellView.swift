import SwiftUI
import DevHavenCore

struct WorkspaceShellView: View {
    @Bindable var viewModel: NativeAppViewModel
    @State private var isProjectPickerPresented = false
    @StateObject private var terminalStoreRegistry = WorkspaceTerminalStoreRegistry()

    var body: some View {
        HStack(spacing: 0) {
            WorkspaceProjectListView(
                projects: viewModel.openWorkspaceProjects,
                activeProjectPath: viewModel.activeWorkspaceProjectPath,
                canOpenMoreProjects: !viewModel.availableWorkspaceProjects.isEmpty,
                onSelectProject: viewModel.activateWorkspaceProject,
                onOpenProjectPicker: { isProjectPickerPresented = true },
                onCloseProject: viewModel.closeWorkspaceProject,
                onExit: viewModel.exitWorkspace
            )
            .frame(width: 220)

            workspaceContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(NativeTheme.window)
        }
        .background(NativeTheme.window)
        .onAppear {
            syncTerminalStores()
            warmActiveWorkspace()
            WorkspaceLaunchDiagnostics.shared.recordShellMounted(
                activeProjectPath: viewModel.activeWorkspaceProjectPath,
                openSessionCount: viewModel.openWorkspaceSessions.count
            )
        }
        .onChange(of: viewModel.openWorkspaceProjectPaths) { _, _ in
            syncTerminalStores()
            warmActiveWorkspace()
        }
        .onChange(of: viewModel.activeWorkspaceProjectPath) { _, _ in
            warmActiveWorkspace()
        }
        .onChange(of: viewModel.activeWorkspaceLaunchRequest?.paneId) { _, _ in
            warmActiveWorkspace()
        }
        .sheet(isPresented: $isProjectPickerPresented) {
            WorkspaceProjectPickerView(
                projects: viewModel.availableWorkspaceProjects,
                onOpenProject: { path in
                    viewModel.enterWorkspace(path)
                    isProjectPickerPresented = false
                },
                onClose: { isProjectPickerPresented = false }
            )
            .preferredColorScheme(.dark)
        }
    }

    @ViewBuilder
    private var workspaceContent: some View {
        if viewModel.openWorkspaceProjects.isEmpty {
            ContentUnavailableView(
                "没有已打开项目",
                systemImage: "terminal",
                description: Text("当前 workspace 中没有可展示的项目。")
            )
            .foregroundStyle(NativeTheme.textSecondary)
        } else {
            ZStack {
                ForEach(viewModel.openWorkspaceSessions) { session in
                    if let project = viewModel.snapshot.projects.first(where: { $0.path == session.projectPath }) {
                        WorkspaceHostView(
                            viewModel: viewModel,
                            project: project,
                            workspace: session.controller,
                            terminalSessionStore: terminalStoreRegistry.store(for: session.projectPath)
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .opacity(session.projectPath == viewModel.activeWorkspaceProjectPath ? 1 : 0)
                        .allowsHitTesting(session.projectPath == viewModel.activeWorkspaceProjectPath)
                        .accessibilityHidden(session.projectPath != viewModel.activeWorkspaceProjectPath)
                    }
                }
            }
        }
    }

    private func syncTerminalStores() {
        terminalStoreRegistry.syncRetainedProjectPaths(Set(viewModel.openWorkspaceProjectPaths))
    }

    private func warmActiveWorkspace() {
        _ = terminalStoreRegistry.warmActiveWorkspaceSession(
            sessions: viewModel.openWorkspaceSessions,
            activeProjectPath: viewModel.activeWorkspaceProjectPath
        )
    }
}
