import Foundation
import SwiftUI
import DevHavenCore

struct WorkspaceGitIdeaLogChangesView: View {
    @Bindable var viewModel: WorkspaceGitLogViewModel
    let onOpenDiff: (WorkspaceGitCommitFileChange) -> Void
    @State private var expandedDirectoryIDs = Set<String>()
    @State private var lastExpandedTreeSignature: Int?

    var body: some View {
        let detail = viewModel.selectedCommitDetail
        let projection = detail.map { changeTreeProjection(for: $0.files) }

        VStack(alignment: .leading, spacing: 0) {
            paneHeader(title: "变更", subtitle: changeCountLabel)
            Divider()
                .overlay(NativeTheme.border)

            changesBrowserToolbar(projection)
            Divider()
                .overlay(NativeTheme.border)

            if viewModel.isLoadingSelectedCommitDetail && detail == nil {
                ProgressView("正在加载变更…")
                    .tint(NativeTheme.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let projection {
                changesBrowserContent(projection)
            } else {
                ContentUnavailableView(
                    "选择一个提交",
                    systemImage: "list.bullet.rectangle.portrait",
                    description: Text("选择提交后，这里会展示该提交的文件变更。")
                )
                .foregroundStyle(NativeTheme.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var changeCountLabel: String {
        if let detail = viewModel.selectedCommitDetail {
            return "\(detail.files.count) 项"
        }
        return "未选择"
    }

    private func changesBrowserToolbar(_ projection: ChangeTreeProjection?) -> some View {
        HStack(spacing: 6) {
            toolbarButton(systemImage: "arrow.left", title: "后退", isEnabled: false) {
                // 结构优先：本轮先对齐 toolbar 布局，交互后续再补齐。
            }
            toolbarButton(systemImage: "arrow.right", title: "前进", isEnabled: false) {
                // 结构优先：本轮先对齐 toolbar 布局，交互后续再补齐。
            }
            toolbarButton(systemImage: "arrow.up.left.and.arrow.down.right", title: "展开全部") {
                expandAllDirectories(in: projection)
            }
            toolbarButton(systemImage: "arrow.down.forward.and.arrow.up.backward", title: "折叠全部") {
                collapseAllDirectories()
            }
            toolbarButton(systemImage: "clock", title: "历史", isEnabled: false) {
                // 结构优先：本轮先对齐 toolbar 布局，交互后续再补齐。
            }
            toolbarButton(systemImage: "eye", title: "显示", isEnabled: false) {
                // 结构优先：本轮先对齐 toolbar 布局，交互后续再补齐。
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(NativeTheme.surface)
    }

    private func toolbarButton(
        systemImage: String,
        title: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.callout)
                .foregroundStyle(isEnabled ? NativeTheme.textSecondary : NativeTheme.textSecondary.opacity(0.5))
                .frame(width: 28, height: 24)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(isEnabled ? title : "\(title)（暂未实现）")
    }

    private func paneHeader(title: String, subtitle: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(NativeTheme.textPrimary)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(NativeTheme.textSecondary)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(NativeTheme.surface)
    }

    @ViewBuilder
    private func changesBrowserContent(_ projection: ChangeTreeProjection) -> some View {
        List {
            ForEach(projection.roots) { node in
                changeTreeNodeView(node)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(NativeTheme.window)
        .onAppear {
            syncExpandedDirectoriesIfNeeded(projection)
        }
        .onChange(of: projection.signature) { _, _ in
            syncExpandedDirectoriesIfNeeded(projection)
        }
    }

    private func changeTreeNodeView(_ node: ChangeTreeNode) -> AnyView {
        if let file = node.file {
            return AnyView(fileRow(for: file))
        }

        return AnyView(
            DisclosureGroup(isExpanded: expansionBinding(for: node.id)) {
                if let children = node.children {
                    ForEach(children) { child in
                        changeTreeNodeView(child)
                    }
                }
            } label: {
                directoryRow(node)
            }
        )
    }

    private func expansionBinding(for directoryID: String) -> Binding<Bool> {
        Binding(
            get: { expandedDirectoryIDs.contains(directoryID) },
            set: { isExpanded in
                if isExpanded {
                    expandedDirectoryIDs.insert(directoryID)
                } else {
                    expandedDirectoryIDs.remove(directoryID)
                }
            }
        )
    }

    private func directoryRow(_ node: ChangeTreeNode) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.caption)
                .foregroundStyle(NativeTheme.textSecondary)
                .frame(width: 12, height: 16, alignment: .top)
            Text(node.title)
                .font(.callout)
                .foregroundStyle(NativeTheme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
        }
        .padding(.vertical, 3)
    }

    private func fileRow(for file: WorkspaceGitCommitFileChange) -> some View {
        Button {
            viewModel.selectCommitFile(file.path)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon(for: file.status))
                    .font(.caption)
                    .foregroundStyle(color(for: file.status))
                    .frame(width: 12, height: 16, alignment: .top)

                VStack(alignment: .leading, spacing: 2) {
                    Text(primaryFileName(for: file))
                        .font(.callout.monospaced())
                        .foregroundStyle(NativeTheme.textPrimary)
                        .lineLimit(1)
                    if let subtitle = fileSubtitle(for: file) {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(NativeTheme.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                Text(file.status.rawValue.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(NativeTheme.textSecondary)
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(viewModel.selectedFilePath == file.path ? NativeTheme.accent.opacity(0.14) : Color.clear)
            .clipShape(.rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                openFileDiff(file)
            }
        )
        .contextMenu {
            Button("打开差异") {
                openFileDiff(file)
            }
        }
        .help("双击打开差异")
        .accessibilityAction(named: Text("打开差异")) {
            openFileDiff(file)
        }
    }

    private func openFileDiff(_ file: WorkspaceGitCommitFileChange) {
        viewModel.selectCommitFile(file.path)
        onOpenDiff(file)
    }

    private func fileSubtitle(for file: WorkspaceGitCommitFileChange) -> String? {
        secondaryPathSubtitle(for: file)
    }

    private func primaryFileName(for file: WorkspaceGitCommitFileChange) -> String {
        let fileName = (file.path as NSString).lastPathComponent
        return fileName.isEmpty ? file.path : fileName
    }

    private func secondaryPathSubtitle(for file: WorkspaceGitCommitFileChange) -> String? {
        var parts = [String]()
        let parentPath = (file.path as NSString).deletingLastPathComponent
        if !parentPath.isEmpty && parentPath != file.path {
            parts.append(parentPath)
        }

        switch file.status {
        case .renamed:
            if let oldPath = file.oldPath {
                parts.append("从 \((oldPath as NSString).lastPathComponent) 重命名")
            }
            return parts.isEmpty ? "已重命名" : parts.joined(separator: " · ")
        case .copied:
            if let oldPath = file.oldPath {
                parts.append("从 \((oldPath as NSString).lastPathComponent) 复制")
            }
            return parts.isEmpty ? "已复制" : parts.joined(separator: " · ")
        case .typeChanged:
            parts.append("文件类型已变化")
            return parts.joined(separator: " · ")
        case .unmerged:
            parts.append("存在未解决冲突")
            return parts.joined(separator: " · ")
        default:
            return parts.isEmpty ? nil : parts.joined(separator: " / ")
        }
    }

    private func changeTreeProjection(for files: [WorkspaceGitCommitFileChange]) -> ChangeTreeProjection {
        let signature = changeTreeProjectionSignature(for: files)
        if let cached = ChangeTreeProjectionCache.shared.projection(for: signature) {
            return cached
        }

        let roots = ChangeTreeBuilder(files: files, fileNameProvider: primaryFileName(for:)).build()
        let projection = ChangeTreeProjection(
            roots: roots,
            signature: signature,
            allDirectoryIDs: allDirectoryIDs(in: roots)
        )
        ChangeTreeProjectionCache.shared.store(projection, for: signature)
        return projection
    }

    private func expandAllDirectories(in projection: ChangeTreeProjection?) {
        expandedDirectoryIDs = projection?.allDirectoryIDs ?? []
    }

    private func collapseAllDirectories() {
        expandedDirectoryIDs.removeAll()
    }

    private func allDirectoryIDs(in roots: [ChangeTreeNode]) -> Set<String> {
        var ids = Set<String>()
        func collect(_ node: ChangeTreeNode) {
            if node.file == nil {
                ids.insert(node.id)
                node.children?.forEach(collect)
            }
        }
        roots.forEach(collect)
        return ids
    }

    private func syncExpandedDirectoriesIfNeeded(_ projection: ChangeTreeProjection) {
        guard lastExpandedTreeSignature != projection.signature else {
            return
        }
        lastExpandedTreeSignature = projection.signature
        expandedDirectoryIDs = projection.allDirectoryIDs
    }

    private func color(for status: WorkspaceGitCommitFileStatus) -> Color {
        switch status {
        case .added:
            return .green
        case .modified:
            return NativeTheme.accent
        case .deleted:
            return .red
        case .renamed, .copied:
            return .orange
        case .typeChanged, .unmerged, .unknown:
            return NativeTheme.textSecondary
        }
    }

    private func icon(for status: WorkspaceGitCommitFileStatus) -> String {
        switch status {
        case .added:
            return "plus.square.fill"
        case .modified:
            return "pencil.line"
        case .deleted:
            return "trash.fill"
        case .renamed:
            return "arrow.left.arrow.right.square"
        case .copied:
            return "square.on.square"
        case .typeChanged:
            return "square.3.layers.3d"
        case .unmerged:
            return "exclamationmark.triangle.fill"
        case .unknown:
            return "questionmark.square"
        }
    }
}

private struct ChangeTreeProjection {
    let roots: [ChangeTreeNode]
    let signature: Int
    let allDirectoryIDs: Set<String>
}

private final class ChangeTreeProjectionCache: @unchecked Sendable {
    static let shared = ChangeTreeProjectionCache()
    private static let maxEntryCount = 64

    private let lock = NSLock()
    private var cachedProjections: [Int: ChangeTreeProjection] = [:]

    func projection(for signature: Int) -> ChangeTreeProjection? {
        lock.lock()
        defer { lock.unlock() }
        return cachedProjections[signature]
    }

    func store(_ projection: ChangeTreeProjection, for signature: Int) {
        lock.lock()
        cachedProjections[signature] = projection
        if cachedProjections.count > Self.maxEntryCount {
            cachedProjections.removeAll(keepingCapacity: true)
        }
        lock.unlock()
    }
}

private struct ChangeTreeNode: Identifiable {
    let id: String
    let title: String
    let children: [ChangeTreeNode]?
    let file: WorkspaceGitCommitFileChange?
}

private struct ChangeTreeBuilder {
    let files: [WorkspaceGitCommitFileChange]
    let fileNameProvider: (WorkspaceGitCommitFileChange) -> String

    func build() -> [ChangeTreeNode] {
        let root = MutableNode(title: "")
        for file in files {
            insert(file, into: root)
        }
        return root.sortedChildren()
    }

    private func insert(_ file: WorkspaceGitCommitFileChange, into root: MutableNode) {
        let parentPath = (file.path as NSString).deletingLastPathComponent
        let components = parentPath
            .split(separator: "/")
            .map(String.init)
        var current = root
        var runningPath = ""

        for component in components where !component.isEmpty {
            runningPath = runningPath.isEmpty ? component : "\(runningPath)/\(component)"
            current = current.childDirectory(named: component, path: runningPath)
        }

        let fileNode = ChangeTreeNode(
            id: "file:\(file.path)",
            title: fileNameProvider(file),
            children: nil,
            file: file
        )
        current.fileChildren.append(fileNode)
    }

    private final class MutableNode {
        let title: String
        private let path: String
        private var directoryChildren: [MutableNode] = []
        var fileChildren: [ChangeTreeNode] = []

        init(title: String, path: String = "") {
            self.title = title
            self.path = path
        }

        func childDirectory(named title: String, path: String) -> MutableNode {
            if let existing = directoryChildren.first(where: { $0.path == path }) {
                return existing
            }
            let child = MutableNode(title: title, path: path)
            directoryChildren.append(child)
            return child
        }

        func sortedChildren() -> [ChangeTreeNode] {
            let directoryNodes = directoryChildren
                .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                .map {
                    ChangeTreeNode(
                        id: "dir:\($0.path)",
                        title: $0.title,
                        children: $0.sortedChildren(),
                        file: nil
                    )
                }

            let fileNodes = fileChildren
                .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

            return directoryNodes + fileNodes
        }
    }
}

private func changeTreeProjectionSignature(for files: [WorkspaceGitCommitFileChange]) -> Int {
    var hasher = Hasher()
    hasher.combine(files.count)
    for file in files {
        hasher.combine(file.path)
        hasher.combine(file.oldPath)
        hasher.combine(file.status.rawValue)
    }
    return hasher.finalize()
}
