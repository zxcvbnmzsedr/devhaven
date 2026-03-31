import SwiftUI
import AppKit
import DevHavenCore

private struct WorkspaceProjectCreationContext: Identifiable {
    enum Kind {
        case file
        case folder
    }

    let kind: Kind
    let targetPath: String?

    var id: String {
        "\(kind)-\(targetPath ?? "root")"
    }

    var title: String {
        switch kind {
        case .file:
            return "新建文件"
        case .folder:
            return "新建文件夹"
        }
    }
}

private struct WorkspaceProjectRenameContext: Identifiable {
    let path: String
    let currentName: String

    var id: String { path }
}

private struct WorkspaceProjectDeleteRequest: Identifiable {
    let path: String
    let name: String
    let isDirectory: Bool

    var id: String { path }
}

struct WorkspaceProjectToolWindowHostView: View {
    @Bindable var viewModel: NativeAppViewModel
    @State private var creationContext: WorkspaceProjectCreationContext?
    @State private var renameContext: WorkspaceProjectRenameContext?
    @State private var deleteRequest: WorkspaceProjectDeleteRequest?

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(NativeTheme.window)
            .contentShape(Rectangle())
            .onTapGesture {
                viewModel.setWorkspaceFocusedArea(.sideToolWindow(.project))
            }
            .onAppear {
                viewModel.prepareActiveWorkspaceProjectTreeState()
            }
            .sheet(item: $creationContext) { context in
                WorkspaceProjectNameEditorSheet(
                    title: context.title,
                    initialName: "",
                    confirmTitle: "创建",
                    onSubmit: { name in
                        viewModel.createWorkspaceProjectTreeItem(
                            named: name,
                            isDirectory: context.kind == .folder,
                            under: context.targetPath
                        )
                        creationContext = nil
                    },
                    onClose: { creationContext = nil }
                )
                .preferredColorScheme(.dark)
            }
            .sheet(item: $renameContext) { context in
                WorkspaceProjectNameEditorSheet(
                    title: "重命名",
                    initialName: context.currentName,
                    confirmTitle: "应用",
                    onSubmit: { name in
                        viewModel.renameWorkspaceProjectTreeNode(context.path, to: name)
                        renameContext = nil
                    },
                    onClose: { renameContext = nil }
                )
                .preferredColorScheme(.dark)
            }
            .alert(item: $deleteRequest) { request in
                Alert(
                    title: Text("移到废纸篓"),
                    message: Text("确定要将\(request.isDirectory ? "文件夹" : "文件")“\(request.name)”移到废纸篓吗？"),
                    primaryButton: .destructive(Text("移到废纸篓")) {
                        viewModel.trashWorkspaceProjectTreeNode(request.path)
                    },
                    secondaryButton: .cancel()
                )
            }
    }

    @ViewBuilder
    private var content: some View {
        if let project = viewModel.activeWorkspaceProjectTreeProject {
            if let treeState = viewModel.activeWorkspaceProjectTreeState,
               let displayProjection = viewModel.activeWorkspaceProjectTreeDisplayProjection,
               treeState.rootProjectPath == project.path {
                WorkspaceProjectTreeView(
                    project: project,
                    treeState: treeState,
                    displayProjection: displayProjection,
                    isRefreshing: viewModel.activeWorkspaceProjectTreeIsRefreshing,
                    onRefresh: { viewModel.refreshWorkspaceProjectTree(for: project.path) },
                    onCreateFile: { targetPath in
                        creationContext = WorkspaceProjectCreationContext(kind: .file, targetPath: targetPath)
                    },
                    onCreateFolder: { targetPath in
                        creationContext = WorkspaceProjectCreationContext(kind: .folder, targetPath: targetPath)
                    },
                    onSelectNode: { path in
                        viewModel.selectWorkspaceProjectTreeNode(path, in: project.path)
                    },
                    onToggleDirectory: { path in
                        viewModel.toggleWorkspaceProjectTreeDirectory(path, in: project.path)
                    },
                    onPreviewFile: { filePath in
                        viewModel.previewWorkspaceProjectTreeNode(filePath, in: project.path)
                    },
                    onOpenFile: { filePath in
                        viewModel.openWorkspaceProjectTreeNode(filePath, in: project.path)
                    },
                    isKeyboardCaptureEnabled: viewModel.workspaceFocusedArea == .sideToolWindow(.project),
                    onRefreshNode: { path in
                        viewModel.refreshWorkspaceProjectTreeNode(path, in: project.path)
                    },
                    onRenameNode: { path in
                        renameContext = WorkspaceProjectRenameContext(
                            path: path,
                            currentName: URL(fileURLWithPath: path).lastPathComponent
                        )
                    },
                    onTrashNode: { path in
                        deleteRequest = WorkspaceProjectDeleteRequest(
                            path: path,
                            name: URL(fileURLWithPath: path).lastPathComponent,
                            isDirectory: FileManager.default.directoryExists(atPath: path)
                        )
                    },
                    onRevealInFinder: { path in
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    }
                )
            } else {
                ProgressView("正在载入 Project 目录树…")
                    .foregroundStyle(NativeTheme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            ContentUnavailableView(
                "Project 目录树不可用",
                systemImage: "folder",
                description: Text("请先打开一个项目或 worktree，再使用 Project 工具窗。")
            )
            .foregroundStyle(NativeTheme.textSecondary)
        }
    }
}

private struct WorkspaceProjectNameEditorSheet: View {
    let title: String
    let initialName: String
    let confirmTitle: String
    let onSubmit: (String) -> Void
    let onClose: () -> Void

    @State private var name: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(NativeTheme.textPrimary)

            TextField("请输入名称", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    submit()
                }

            HStack {
                Spacer(minLength: 0)
                Button("取消", action: onClose)
                    .buttonStyle(.borderless)
                Button(confirmTitle, action: submit)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
        .background(NativeTheme.window)
        .onAppear {
            name = initialName
        }
    }

    private func submit() {
        onSubmit(name)
    }
}

private extension FileManager {
    func directoryExists(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    func regularFileExists(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }
}
