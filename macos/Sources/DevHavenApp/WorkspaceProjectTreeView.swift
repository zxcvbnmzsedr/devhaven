import SwiftUI
import AppKit
import DevHavenCore

struct WorkspaceProjectTreeView: View {
    @FocusState private var isTreeFocused: Bool
    @State private var speedSearchQuery = ""

    let project: Project
    let treeState: WorkspaceProjectTreeState
    let displayProjection: WorkspaceProjectTreeDisplayProjection
    let isRefreshing: Bool
    let onRefresh: () -> Void
    let onCreateFile: (String?) -> Void
    let onCreateFolder: (String?) -> Void
    let onSelectNode: (String) -> Void
    let onToggleDirectory: (String) -> Void
    let onPreviewFile: (String) -> Void
    let onOpenFile: (String) -> Void
    let isKeyboardCaptureEnabled: Bool
    let onRefreshNode: (String?) -> Void
    let onRenameNode: (String) -> Void
    let onTrashNode: (String) -> Void
    let onRevealInFinder: (String) -> Void

    private var isSpeedSearchActive: Bool {
        !speedSearchQuery.isEmpty
    }

    var body: some View {
        let displayRootNodes = displayProjection.rootNodes
        let filteredDisplayRootNodes = workspaceProjectTreeFilteredNodes(
            displayRootNodes,
            query: speedSearchQuery
        )
        let visibleNodes = flattenVisibleNodes(filteredDisplayRootNodes)

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
            } else if filteredDisplayRootNodes.isEmpty {
                ContentUnavailableView(
                    "没有匹配项",
                    systemImage: "magnifyingglass",
                    description: Text("未找到包含“\(speedSearchQuery)”的文件或目录。按 Esc 清空过滤。")
                )
                .foregroundStyle(NativeTheme.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    WorkspaceProjectTreeBranchView(
                        nodes: filteredDisplayRootNodes,
                        level: 0,
                        treeState: treeState,
                        searchQuery: speedSearchQuery,
                        forceExpandMatches: isSpeedSearchActive,
                        onCreateFile: onCreateFile,
                        onCreateFolder: onCreateFolder,
                        onSelectNode: onSelectNode,
                        onToggleDirectory: onToggleDirectory,
                        onPreviewFile: onPreviewFile,
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
            syncSelectionToVisibleNodes(currentVisibleNodes())
        }
        .onChange(of: speedSearchQuery) { _, _ in
            syncSelectionToVisibleNodes(currentVisibleNodes())
        }
        .onMoveCommand { direction in
            handleMoveCommand(direction, visibleNodes: visibleNodes)
        }
        .background {
            WorkspaceProjectTreeKeyCaptureView(
                isEnabled: isKeyboardCaptureEnabled,
                onInput: appendSpeedSearchCharacter(_:),
                onBackspace: removeSpeedSearchCharacter,
                onClear: clearSpeedSearch
            )
            .frame(width: 0, height: 0)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                    Group {
                        if isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                                .tint(NativeTheme.textPrimary)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(NativeTheme.textPrimary)
                        }
                    }
                    .frame(width: 28, height: 28)
                    .background(NativeTheme.surface)
                    .clipShape(.rect(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(isRefreshing)
                .help("刷新目录树")
            }

            if isSpeedSearchActive {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NativeTheme.textSecondary)
                    Text(speedSearchQuery)
                        .font(.caption.monospaced())
                        .foregroundStyle(NativeTheme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text("Esc 清空")
                        .font(.caption2)
                        .foregroundStyle(NativeTheme.textSecondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(NativeTheme.surface)
                .clipShape(.rect(cornerRadius: 10))
            } else {
                Text("直接键入可快速过滤当前 Project 树")
                    .font(.caption)
                    .foregroundStyle(NativeTheme.textSecondary)
            }
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

    private func flattenVisibleNodes(_ nodes: [WorkspaceProjectTreeDisplayNode]) -> [WorkspaceProjectTreeDisplayNode] {
        var result: [WorkspaceProjectTreeDisplayNode] = []
        for node in nodes {
            result.append(node)
            if node.isDirectory,
               (isSpeedSearchActive || treeState.isExpanded(node.path)) {
                result.append(contentsOf: flattenVisibleNodes(node.children))
            }
        }
        return result
    }

    private func currentVisibleNodes() -> [WorkspaceProjectTreeDisplayNode] {
        flattenVisibleNodes(
            workspaceProjectTreeFilteredNodes(
                displayProjection.rootNodes,
                query: speedSearchQuery
            )
        )
    }

    private func handleMoveCommand(
        _ direction: MoveCommandDirection,
        visibleNodes: [WorkspaceProjectTreeDisplayNode]
    ) {
        guard let selectedPath = treeState.selectedPath,
              let currentIndex = visibleNodes.firstIndex(where: { $0.matchesSelection(selectedPath) })
        else {
            if let first = visibleNodes.first {
                selectNode(first)
            }
            return
        }

        let currentNode = visibleNodes[currentIndex]
        switch direction {
        case .up:
            guard visibleNodes.indices.contains(currentIndex - 1) else { return }
            selectNode(visibleNodes[currentIndex - 1])
        case .down:
            guard visibleNodes.indices.contains(currentIndex + 1) else { return }
            selectNode(visibleNodes[currentIndex + 1])
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
                    selectNode(firstChild)
                }
            }
        @unknown default:
            break
        }
    }

    private func selectNode(_ node: WorkspaceProjectTreeDisplayNode) {
        onSelectNode(node.path)
        guard !node.isDirectory else {
            return
        }
        onPreviewFile(node.path)
    }

    private func appendSpeedSearchCharacter(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .controlCharacters)
        guard !trimmed.isEmpty else {
            return
        }
        speedSearchQuery += trimmed
    }

    private func removeSpeedSearchCharacter() {
        guard !speedSearchQuery.isEmpty else {
            return
        }
        speedSearchQuery.removeLast()
    }

    private func clearSpeedSearch() {
        guard !speedSearchQuery.isEmpty else {
            return
        }
        speedSearchQuery = ""
    }

    private func syncSelectionToVisibleNodes(_ visibleNodes: [WorkspaceProjectTreeDisplayNode]) {
        guard let firstVisibleNode = visibleNodes.first else {
            return
        }
        guard let selectedPath = treeState.selectedPath,
              visibleNodes.contains(where: { $0.matchesSelection(selectedPath) })
        else {
            selectNode(firstVisibleNode)
            return
        }
    }
}

private struct WorkspaceProjectTreeBranchView: View {
    let nodes: [WorkspaceProjectTreeDisplayNode]
    let level: Int
    let treeState: WorkspaceProjectTreeState
    let searchQuery: String
    let forceExpandMatches: Bool
    let onCreateFile: (String?) -> Void
    let onCreateFolder: (String?) -> Void
    let onSelectNode: (String) -> Void
    let onToggleDirectory: (String) -> Void
    let onPreviewFile: (String) -> Void
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
                    isExpanded: node.isDirectory && (forceExpandMatches || treeState.isExpanded(node.path)),
                    searchQuery: searchQuery,
                    onSelect: { onSelectNode(node.path) },
                    onToggleDirectory: {
                        guard node.isDirectory else { return }
                        guard !forceExpandMatches else { return }
                        onToggleDirectory(node.path)
                    },
                    onPreviewFile: {
                        guard !node.isDirectory else { return }
                        onPreviewFile(node.path)
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

                if node.isDirectory, (forceExpandMatches || treeState.isExpanded(node.path)) {
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
                                searchQuery: searchQuery,
                                forceExpandMatches: forceExpandMatches,
                                onCreateFile: onCreateFile,
                                onCreateFolder: onCreateFolder,
                                onSelectNode: onSelectNode,
                                onToggleDirectory: onToggleDirectory,
                                onPreviewFile: onPreviewFile,
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
    let searchQuery: String
    let onSelect: () -> Void
    let onToggleDirectory: () -> Void
    let onPreviewFile: () -> Void
    let onOpenFile: () -> Void
    let onCreateFile: () -> Void
    let onCreateFolder: () -> Void
    let onRefreshNode: () -> Void
    let onRenameNode: () -> Void
    let onTrashNode: () -> Void
    let onRevealInFinder: () -> Void

    var body: some View {
        let canExpand = node.isDirectory
        let isLinkedDirectory = node.isLinkedDirectory

        HStack(spacing: 6) {
            Spacer()
                .frame(width: CGFloat(level) * 14)

            if canExpand {
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

            Text(workspaceProjectTreeHighlightedTitle(node.name, query: searchQuery))
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
            if !canExpand && !isLinkedDirectory {
                onPreviewFile()
            }
        }
        .onTapGesture(count: 2) {
            onSelect()
            if canExpand {
                onToggleDirectory()
            } else {
                onOpenFile()
            }
        }
        .contextMenu {
            if !canExpand {
                Button("在预览标签页打开") {
                    onPreviewFile()
                }
                Button("打开") {
                    onOpenFile()
                }
                Divider()
            }
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

enum WorkspaceProjectTreeKeyCaptureAction: Equatable {
    case clear
    case backspace
    case input(String)
}

func workspaceProjectTreeKeyCaptureAction(
    isEnabled: Bool,
    keyCode: UInt16,
    charactersIgnoringModifiers: String,
    modifierFlags: NSEvent.ModifierFlags,
    firstResponderIsTextInput: Bool
) -> WorkspaceProjectTreeKeyCaptureAction? {
    guard isEnabled, !firstResponderIsTextInput else {
        return nil
    }
    guard modifierFlags.intersection([.command, .option, .control]).isEmpty else {
        return nil
    }

    switch keyCode {
    case 53:
        return .clear
    case 51, 117:
        return .backspace
    default:
        break
    }

    guard !charactersIgnoringModifiers.isEmpty,
          charactersIgnoringModifiers.unicodeScalars.allSatisfy({ !$0.properties.isWhitespace || $0 == " " }),
          charactersIgnoringModifiers.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
    else {
        return nil
    }
    return .input(charactersIgnoringModifiers)
}

private struct WorkspaceProjectTreeKeyCaptureView: NSViewRepresentable {
    let isEnabled: Bool
    let onInput: (String) -> Void
    let onBackspace: () -> Void
    let onClear: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isEnabled: { isEnabled },
            onInput: onInput,
            onBackspace: onBackspace,
            onClear: onClear
        )
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.installIfNeeded()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isEnabled = { isEnabled }
        context.coordinator.onInput = onInput
        context.coordinator.onBackspace = onBackspace
        context.coordinator.onClear = onClear
        context.coordinator.installIfNeeded()
    }

    final class Coordinator {
        var isEnabled: () -> Bool
        var onInput: (String) -> Void
        var onBackspace: () -> Void
        var onClear: () -> Void
        private var monitor: Any?

        init(
            isEnabled: @escaping () -> Bool,
            onInput: @escaping (String) -> Void,
            onBackspace: @escaping () -> Void,
            onClear: @escaping () -> Void
        ) {
            self.isEnabled = isEnabled
            self.onInput = onInput
            self.onBackspace = onBackspace
            self.onClear = onClear
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }

        func installIfNeeded() {
            guard monitor == nil else {
                return
            }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else {
                    return event
                }
                let action = workspaceProjectTreeKeyCaptureAction(
                    isEnabled: self.isEnabled(),
                    keyCode: event.keyCode,
                    charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
                    modifierFlags: event.modifierFlags,
                    firstResponderIsTextInput: MainActor.assumeIsolated {
                        (NSApp.keyWindow?.firstResponder as? NSTextView) != nil
                    }
                )
                switch action {
                case .clear:
                    self.onClear()
                    return nil
                case .backspace:
                    self.onBackspace()
                    return nil
                case let .input(characters):
                    self.onInput(characters)
                    return nil
                case nil:
                    return event
                }
            }
        }
    }
}

func workspaceProjectTreeFilteredNodes(
    _ nodes: [WorkspaceProjectTreeDisplayNode],
    query: String
) -> [WorkspaceProjectTreeDisplayNode] {
    let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedQuery.isEmpty else {
        return nodes
    }

    return nodes.compactMap { node in
        let filteredChildren = workspaceProjectTreeFilteredNodes(node.children, query: normalizedQuery)
        if workspaceProjectTreeNodeMatchesSpeedSearch(node, query: normalizedQuery) || !filteredChildren.isEmpty {
            var copy = node
            copy.children = filteredChildren
            return copy
        }
        return nil
    }
}

func workspaceProjectTreeNodeMatchesSpeedSearch(
    _ node: WorkspaceProjectTreeDisplayNode,
    query: String
) -> Bool {
    let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedQuery.isEmpty else {
        return true
    }

    let candidates = [node.name, node.path]
        + node.compactedDirectoryPaths
        + node.compactedDirectoryPaths.map { URL(fileURLWithPath: $0).lastPathComponent }
    return candidates.contains { candidate in
        candidate.localizedCaseInsensitiveContains(normalizedQuery)
    }
}

private func workspaceProjectTreeHighlightedTitle(
    _ title: String,
    query: String
) -> AttributedString {
    var attributed = AttributedString(title)
    let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedQuery.isEmpty,
          let range = attributed.range(
            of: normalizedQuery,
            options: [.caseInsensitive]
          )
    else {
        return attributed
    }

    attributed[range].foregroundColor = .primary
    attributed[range].backgroundColor = Color.yellow.opacity(0.35)
    return attributed
}
