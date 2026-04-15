import SwiftUI
import AppKit
import DevHavenCore

struct WorkspaceCommitRollbackSheet: View {
    let executionPath: String
    let changes: [WorkspaceCommitChange]
    let initialIncludedPaths: Set<String>
    let onSubmit: ([String], Bool) -> Void
    let onClose: () -> Void

    @AppStorage("workspace.commit.rollback.deleteLocallyAddedFiles")
    private var deleteLocallyAddedFiles = false
    @State private var selectedPaths: Set<String>

    init(
        executionPath: String,
        changes: [WorkspaceCommitChange],
        initialIncludedPaths: Set<String>,
        onSubmit: @escaping ([String], Bool) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.executionPath = executionPath
        self.changes = changes
        self.initialIncludedPaths = initialIncludedPaths
        self.onSubmit = onSubmit
        self.onClose = onClose

        let availablePaths = Set(changes.map(\.path))
        let seededPaths = initialIncludedPaths.intersection(availablePaths)
        _selectedPaths = State(initialValue: seededPaths.isEmpty ? availablePaths : seededPaths)
    }

    private var versionedChanges: [WorkspaceCommitChange] {
        changes.filter { $0.group != .untracked }
    }

    private var untrackedChanges: [WorkspaceCommitChange] {
        changes.filter { $0.group == .untracked }
    }

    private var selectedChanges: [WorkspaceCommitChange] {
        changes.filter { selectedPaths.contains($0.path) }
    }

    private var selectedTrackedNewCount: Int {
        selectedChanges.count { $0.status == .added && $0.group != .untracked }
    }

    private var selectedUntrackedCount: Int {
        selectedChanges.count { $0.group == .untracked }
    }

    private var selectedModifiedCount: Int {
        selectedChanges.count { change in
            change.group != .untracked && (change.status == .modified || change.status == .renamed || change.status == .copied)
        }
    }

    private var selectedDeletedCount: Int {
        selectedChanges.count { $0.status == .deleted }
    }

    private var selectedLocalAdditionCount: Int {
        selectedTrackedNewCount + selectedUntrackedCount
    }

    private var effectiveSelectionCount: Int {
        selectedChanges.count { change in
            if change.group == .untracked {
                return deleteLocallyAddedFiles
            }
            return true
        }
    }

    private var canSubmit: Bool {
        effectiveSelectionCount > 0
    }

    private var addedLegendValue: String {
        switch (selectedTrackedNewCount, selectedUntrackedCount) {
        case let (trackedNew, untracked) where trackedNew > 0 && untracked > 0:
            return "\(trackedNew)+\(untracked)"
        case let (trackedNew, _) where trackedNew > 0:
            return "\(trackedNew)"
        case let (_, untracked) where untracked > 0:
            return "\(untracked)"
        default:
            return ""
        }
    }

    private var localAdditionHint: String {
        if selectedLocalAdditionCount == 0 {
            return "当前选中项里没有本地新增文件。"
        }
        if deleteLocallyAddedFiles {
            return "勾选后，新增文件和未跟踪文件会从本地删除。"
        }
        return "不勾选时，新增文件会保留在本地；未跟踪文件不会被删除。"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("还原变更")
                .font(.title3.weight(.semibold))
                .foregroundStyle(NativeTheme.textPrimary)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("已选 \(selectedPaths.count) / \(changes.count)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(NativeTheme.textSecondary)

                Spacer(minLength: 0)

                Button("全选") {
                    selectedPaths = Set(changes.map(\.path))
                }
                .buttonStyle(.plain)
                .foregroundStyle(NativeTheme.textSecondary)

                Button("清空") {
                    selectedPaths.removeAll()
                }
                .buttonStyle(.plain)
                .foregroundStyle(NativeTheme.textSecondary)
            }

            rollbackLegend

            VStack(alignment: .leading, spacing: 8) {
                Toggle("删除本地新增文件", isOn: $deleteLocallyAddedFiles)
                    .toggleStyle(.checkbox)
                    .disabled(selectedLocalAdditionCount == 0)

                Text(localAdditionHint)
                    .font(.caption)
                    .foregroundStyle(
                        selectedLocalAdditionCount == 0
                            ? NativeTheme.textSecondary.opacity(0.7)
                            : NativeTheme.textSecondary
                    )
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !versionedChanges.isEmpty {
                        section(title: "变更", changes: versionedChanges)
                    }

                    if !untrackedChanges.isEmpty {
                        section(title: "未跟踪文件", changes: untrackedChanges)
                    }
                }
            }
            .frame(minHeight: 320, maxHeight: .infinity)
            .background(NativeTheme.surface)
            .clipShape(.rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(NativeTheme.border, lineWidth: 1)
            }

            HStack {
                Spacer(minLength: 0)
                Button("取消", action: onClose)
                Button("还原") {
                    onSubmit(Array(selectedPaths).sorted(), deleteLocallyAddedFiles)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)
            }
        }
        .padding(20)
        .frame(width: 560, height: 660)
        .background(NativeTheme.window)
    }

    private var rollbackLegend: some View {
        HStack(spacing: 10) {
            legendChip(
                countText: addedLegendValue,
                label: "新增",
                foreground: NativeTheme.success
            )
            legendChip(
                countText: selectedModifiedCount > 0 ? "\(selectedModifiedCount)" : "",
                label: "修改",
                foreground: NativeTheme.accent
            )
            legendChip(
                countText: selectedDeletedCount > 0 ? "\(selectedDeletedCount)" : "",
                label: "删除",
                foreground: NativeTheme.danger
            )
            Spacer(minLength: 0)
        }
    }

    private func section(title: String, changes: [WorkspaceCommitChange]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\(title) \(changes.count) 个文件")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NativeTheme.textPrimary)
                Spacer(minLength: 8)
                Text("已选 \(selectedCount(in: changes))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(NativeTheme.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(NativeTheme.window)

            ForEach(changes) { change in
                row(change)
            }
        }
    }

    private func row(_ change: WorkspaceCommitChange) -> some View {
        Toggle(isOn: binding(for: change.path)) {
            HStack(spacing: 10) {
                Image(nsImage: fileIcon(for: change))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 16, height: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(fileNameText(for: change))
                        .font(.callout.monospaced())
                        .foregroundStyle(NativeTheme.textPrimary)
                        .lineLimit(1)

                    if let subtitle = subtitleText(for: change) {
                        Text(subtitle)
                            .font(.caption.monospaced())
                            .foregroundStyle(NativeTheme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 8)
            }
            .padding(.vertical, 4)
        }
        .toggleStyle(.checkbox)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(selectedPaths.contains(change.path) ? NativeTheme.accent.opacity(0.08) : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(NativeTheme.border.opacity(0.6))
                .frame(height: 1)
        }
    }

    private func legendChip(countText: String, label: String, foreground: Color) -> some View {
        let hasValue = !countText.isEmpty
        return Text(hasValue ? "\(countText) \(label)" : label)
            .font(.caption.weight(.medium))
            .foregroundStyle(hasValue ? foreground : NativeTheme.textSecondary.opacity(0.7))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((hasValue ? foreground : NativeTheme.textSecondary).opacity(0.12))
            .clipShape(.rect(cornerRadius: 999))
    }

    private func binding(for path: String) -> Binding<Bool> {
        Binding(
            get: { selectedPaths.contains(path) },
            set: { isSelected in
                if isSelected {
                    selectedPaths.insert(path)
                } else {
                    selectedPaths.remove(path)
                }
            }
        )
    }

    private func selectedCount(in changes: [WorkspaceCommitChange]) -> Int {
        changes.reduce(into: 0) { partialResult, change in
            if selectedPaths.contains(change.path) {
                partialResult += 1
            }
        }
    }

    private func fileIcon(for change: WorkspaceCommitChange) -> NSImage {
        let fileURL = URL(fileURLWithPath: executionPath, isDirectory: true)
            .appending(path: change.path)
        let icon = NSWorkspace.shared.icon(forFile: fileURL.path)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }

    private func fileNameText(for change: WorkspaceCommitChange) -> String {
        let fileName = (change.path as NSString).lastPathComponent
        return fileName.isEmpty ? change.path : fileName
    }

    private func subtitleText(for change: WorkspaceCommitChange) -> String? {
        var parts = [String]()
        let parentPath = (change.path as NSString).deletingLastPathComponent
        if !parentPath.isEmpty && parentPath != change.path {
            parts.append(parentPath)
        }

        switch change.status {
        case .renamed:
            if let oldPath = change.oldPath {
                parts.append("重命名自 \((oldPath as NSString).lastPathComponent)")
            }
        case .copied:
            if let oldPath = change.oldPath {
                parts.append("复制自 \((oldPath as NSString).lastPathComponent)")
            }
        case .unmerged:
            parts.append("冲突中")
        default:
            break
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
