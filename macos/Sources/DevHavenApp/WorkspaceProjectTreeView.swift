import SwiftUI
import DevHavenCore

struct WorkspaceProjectTreeView: View {
    @FocusState private var isTreeFocused: Bool

    let project: Project
    let treeState: WorkspaceProjectTreeState
    let onRefresh: () -> Void
    let onCreateFile: (String?) -> Void
    let onCreateFolder: (String?) -> Void
    let onSelectNode: (String) -> Void
    let onToggleDirectory: (String) -> Void
    let onOpenFile: (String) -> Void
    let onRefreshNode: (String?) -> Void
    let onRenameNode: (String) -> Void
    let onTrashNode: (String) -> Void
    let onRevealInFinder: (String) -> Void

    private var displayRootNodes: [WorkspaceProjectTreeDisplayNode] {
        treeState.displayRootNodes
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if let errorMessage = treeState.errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Color.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }

            Divider()

            if displayRootNodes.isEmpty {
                ContentUnavailableView(
                    "目录为空",
                    systemImage: "folder",
                    description: Text("当前项目目录下暂无可展示的文件。")
                )
                .foregroundStyle(NativeTheme.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    WorkspaceProjectTreeBranchView(
                        nodes: displayRootNodes,
                        level: 0,
                        treeState: treeState,
                        onCreateFile: onCreateFile,
                        onCreateFolder: onCreateFolder,
                        onSelectNode: onSelectNode,
                        onToggleDirectory: onToggleDirectory,
                        onOpenFile: onOpenFile,
                        onRefreshNode: onRefreshNode,
                        onRenameNode: onRenameNode,
                        onTrashNode: onTrashNode,
                        onRevealInFinder: onRevealInFinder
                    )
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
                }
            }
        }
        .focusable()
        .focused($isTreeFocused)
        .onAppear {
            isTreeFocused = true
        }
        .onMoveCommand(perform: handleMoveCommand)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Project")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(NativeTheme.textPrimary)
                Text(project.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(NativeTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)

            headerIconButton(
                title: "新建文件",
                systemImage: "doc.badge.plus",
                action: { onCreateFile(treeState.selectedPath) }
            )
            headerIconButton(
                title: "新建文件夹",
                systemImage: "folder.badge.plus",
                action: { onCreateFolder(treeState.selectedPath) }
            )
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(NativeTheme.textPrimary)
                    .frame(width: 28, height: 28)
                    .background(NativeTheme.surface)
                    .clipShape(.rect(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .help("刷新目录树")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(NativeTheme.window)
    }

    private func headerIconButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.callout.weight(.semibold))
                .foregroundStyle(NativeTheme.textPrimary)
                .frame(width: 28, height: 28)
                .background(NativeTheme.surface)
                .clipShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(title)
    }

    private var visibleNodes: [WorkspaceProjectTreeDisplayNode] {
        flattenVisibleNodes(displayRootNodes)
    }

    private func flattenVisibleNodes(_ nodes: [WorkspaceProjectTreeDisplayNode]) -> [WorkspaceProjectTreeDisplayNode] {
        var result: [WorkspaceProjectTreeDisplayNode] = []
        for node in nodes {
            result.append(node)
            if node.isDirectory, treeState.isExpanded(node.path) {
                result.append(contentsOf: flattenVisibleNodes(node.children))
            }
        }
        return result
    }

    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        guard let selectedPath = treeState.selectedPath,
              let currentIndex = visibleNodes.firstIndex(where: { $0.matchesSelection(selectedPath) })
        else {
            if let first = visibleNodes.first {
                onSelectNode(first.path)
            }
            return
        }

        let currentNode = visibleNodes[currentIndex]
        switch direction {
        case .up:
            guard visibleNodes.indices.contains(currentIndex - 1) else { return }
            onSelectNode(visibleNodes[currentIndex - 1].path)
        case .down:
            guard visibleNodes.indices.contains(currentIndex + 1) else { return }
            onSelectNode(visibleNodes[currentIndex + 1].path)
        case .left:
            if currentNode.isDirectory, treeState.isExpanded(currentNode.path) {
                onToggleDirectory(currentNode.path)
            } else if let parentPath = currentNode.parentPath {
                onSelectNode(parentPath)
            }
        case .right:
            if currentNode.isDirectory {
                if !treeState.isExpanded(currentNode.path) {
                    onToggleDirectory(currentNode.path)
                } else if let firstChild = currentNode.children.first {
                    onSelectNode(firstChild.path)
                }
            }
        @unknown default:
            break
        }
    }
}

private struct WorkspaceProjectTreeBranchView: View {
    let nodes: [WorkspaceProjectTreeDisplayNode]
    let level: Int
    let treeState: WorkspaceProjectTreeState
    let onCreateFile: (String?) -> Void
    let onCreateFolder: (String?) -> Void
    let onSelectNode: (String) -> Void
    let onToggleDirectory: (String) -> Void
    let onOpenFile: (String) -> Void
    let onRefreshNode: (String?) -> Void
    let onRenameNode: (String) -> Void
    let onTrashNode: (String) -> Void
    let onRevealInFinder: (String) -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(nodes) { node in
                WorkspaceProjectTreeRowView(
                    node: node,
                    level: level,
                    isSelected: node.matchesSelection(treeState.selectedPath),
                    isExpanded: node.isDirectory && treeState.isExpanded(node.path),
                    onSelect: { onSelectNode(node.path) },
                    onToggleDirectory: {
                        guard node.isDirectory else { return }
                        onToggleDirectory(node.path)
                    },
                    onOpenFile: {
                        guard !node.isDirectory else { return }
                        onOpenFile(node.path)
                    },
                    onCreateFile: { onCreateFile(node.path) },
                    onCreateFolder: { onCreateFolder(node.path) },
                    onRefreshNode: { onRefreshNode(node.path) },
                    onRenameNode: { onRenameNode(node.path) },
                    onTrashNode: { onTrashNode(node.path) },
                    onRevealInFinder: { onRevealInFinder(node.path) }
                )

                if node.isDirectory, treeState.isExpanded(node.path) {
                    if treeState.isLoading(node.path) {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("正在载入…")
                                .font(.caption)
                                .foregroundStyle(NativeTheme.textSecondary)
                        }
                        .padding(.leading, CGFloat(level + 1) * 14 + 30)
                        .padding(.vertical, 4)
                    } else {
                        let children = node.children
                        if children.isEmpty {
                            Text("空目录")
                                .font(.caption)
                                .foregroundStyle(NativeTheme.textSecondary)
                                .padding(.leading, CGFloat(level + 1) * 14 + 30)
                                .padding(.vertical, 4)
                        } else {
                            WorkspaceProjectTreeBranchView(
                                nodes: children,
                                level: level + 1,
                                treeState: treeState,
                                onCreateFile: onCreateFile,
                                onCreateFolder: onCreateFolder,
                                onSelectNode: onSelectNode,
                                onToggleDirectory: onToggleDirectory,
                                onOpenFile: onOpenFile,
                                onRefreshNode: onRefreshNode,
                                onRenameNode: onRenameNode,
                                onTrashNode: onTrashNode,
                                onRevealInFinder: onRevealInFinder
                            )
                        }
                    }
                }
            }
        }
    }
}

private struct WorkspaceProjectTreeRowView: View {
    let node: WorkspaceProjectTreeDisplayNode
    let level: Int
    let isSelected: Bool
    let isExpanded: Bool
    let onSelect: () -> Void
    let onToggleDirectory: () -> Void
    let onOpenFile: () -> Void
    let onCreateFile: () -> Void
    let onCreateFolder: () -> Void
    let onRefreshNode: () -> Void
    let onRenameNode: () -> Void
    let onTrashNode: () -> Void
    let onRevealInFinder: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Spacer()
                .frame(width: CGFloat(level) * 14)

            if node.isDirectory {
                Button(action: onToggleDirectory) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NativeTheme.textSecondary)
                        .frame(width: 12, height: 12)
                }
                .buttonStyle(.plain)
            } else {
                Spacer()
                    .frame(width: 12)
            }

            Image(systemName: iconName)
                .font(.callout)
                .foregroundStyle(iconColor)
                .frame(width: 16)

            Text(node.name)
                .font(.callout)
                .foregroundStyle(isSelected ? NativeTheme.textPrimary : NativeTheme.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isSelected ? NativeTheme.accent.opacity(0.18) : Color.clear)
        .clipShape(.rect(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onTapGesture(count: 2) {
            onSelect()
            if node.isDirectory {
                onToggleDirectory()
            } else {
                onOpenFile()
            }
        }
        .contextMenu {
            Button("新建文件") {
                onCreateFile()
            }
            Button("新建文件夹") {
                onCreateFolder()
            }
            Button("刷新") {
                onRefreshNode()
            }
            Divider()
            Button("重命名") {
                onRenameNode()
            }
            Button("在 Finder 中显示") {
                onRevealInFinder()
            }
            Divider()
            Button("移到废纸篓", role: .destructive) {
                onTrashNode()
            }
        }
    }

    private var iconName: String {
        switch node.kind {
        case .directory:
            return isExpanded ? "folder.fill" : "folder"
        case .file:
            return "doc.text"
        case .symlink:
            return "arrow.triangle.branch"
        }
    }

    private var iconColor: Color {
        switch node.kind {
        case .directory:
            return NativeTheme.accent
        case .file:
            return NativeTheme.textSecondary
        case .symlink:
            return .orange
        }
    }
}
