import SwiftUI
import AppKit
import DevHavenCore

struct WorkspaceCommitChangesBrowserView: View {
    @Bindable var viewModel: WorkspaceCommitViewModel
    let onSyncDiffPreviewIfNeeded: (WorkspaceCommitChange) -> Void
    let onOpenDiffPreview: (WorkspaceCommitChange) -> Void

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            Group {
                if let snapshot = viewModel.changesSnapshot, !snapshot.changes.isEmpty {
                    let versionedChanges = snapshot.changes.filter { $0.group != .untracked }
                    let unversionedChanges = snapshot.changes.filter { $0.group == .untracked }

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if !versionedChanges.isEmpty {
                                section(title: "Changes", changes: versionedChanges)
                            }

                            if !unversionedChanges.isEmpty {
                                section(title: "Unversioned Files", changes: unversionedChanges)
                            }
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "暂无变更",
                        systemImage: "checkmark.circle",
                        description: Text("当前工作区没有可提交变更。")
                    )
                    .foregroundStyle(NativeTheme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(NativeTheme.window)
    }

    private var toolbar: some View {
        HStack(spacing: 4) {
            toolbarButton(systemName: "arrow.clockwise", label: "刷新变更") {
                viewModel.refreshChangesSnapshot()
            }

            toolbarButton(
                systemName: viewModel.areAllChangesIncluded ? "checkmark.square.fill" : "checkmark.square",
                label: viewModel.areAllChangesIncluded ? "清空纳入" : "纳入全部"
            ) {
                viewModel.toggleAllInclusion()
            }

            toolbarButton(systemName: "scope", label: "定位到当前选中") {
                guard let path = viewModel.selectedChangePath ?? viewModel.changesSnapshot?.changes.first?.path else {
                    return
                }
                viewModel.selectChange(path)
            }

            Menu {
                Button("清除选中") {
                    viewModel.selectChange(nil)
                }

                Button("刷新") {
                    viewModel.refreshChangesSnapshot()
                }
            } label: {
                toolbarIcon(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 22, height: 22)

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(NativeTheme.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(NativeTheme.border)
                .frame(height: 1)
        }
    }

    private func section(title: String, changes: [WorkspaceCommitChange]) -> some View {
        Group {
            groupHeader(title: title, changes: changes)

            ForEach(changes) { change in
                changeRow(change)
            }
        }
    }

    private func groupHeader(title: String, changes: [WorkspaceCommitChange]) -> some View {
        HStack(spacing: 8) {
            Button {
                toggleSectionInclusion(for: changes)
            } label: {
                Image(systemName: masterInclusionSystemImage(for: changes))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(masterInclusionColor(for: changes))
            }
            .buttonStyle(.plain)

            Text("\(title) \(changes.count) files")
                .font(.caption.weight(.semibold))
                .foregroundStyle(NativeTheme.textPrimary)

            Spacer(minLength: 8)

            Text("\(includedCount(in: changes)) included")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(NativeTheme.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(NativeTheme.window)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(NativeTheme.border)
                .frame(height: 1)
        }
    }

    private func changeRow(_ change: WorkspaceCommitChange) -> some View {
        HStack(spacing: 8) {
            Button {
                viewModel.toggleInclusion(for: change.path)
            } label: {
                Image(systemName: viewModel.includedPaths.contains(change.path) ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(viewModel.includedPaths.contains(change.path) ? NativeTheme.accent : NativeTheme.textSecondary)
            }
            .buttonStyle(.plain)

            Image(nsImage: fileIcon(for: change))
                .resizable()
                .interpolation(.high)
                .frame(width: 16, height: 16)

            inlineTitleRow(change)

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            viewModel.selectedChangePath == change.path
                ? NativeTheme.accent.opacity(0.12)
                : Color.clear
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(NativeTheme.border.opacity(0.65))
                .frame(height: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectChange(change.path)
            onSyncDiffPreviewIfNeeded(change)
        }
        .onTapGesture(count: 2) {
            openChangeDiff(change)
        }
    }

    private func openChangeDiff(_ change: WorkspaceCommitChange) {
        viewModel.selectChange(change.path)
        onOpenDiffPreview(change)
    }

    private func inlineTitleRow(_ change: WorkspaceCommitChange) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(fileNameText(for: change))
                .font(.callout.monospaced())
                .foregroundColor(fileNameColor(for: change))
                .lineLimit(1)

            if let directoryText = directoryText(for: change) {
                Text(" \(directoryText)")
                    .font(.callout.monospaced())
                    .foregroundColor(NativeTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private func fileIcon(for change: WorkspaceCommitChange) -> NSImage {
        let fileURL = URL(fileURLWithPath: viewModel.repositoryContext.executionPath, isDirectory: true)
            .appending(path: change.path)
        let icon = NSWorkspace.shared.icon(forFile: fileURL.path)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }

    private func toolbarButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            toolbarIcon(systemName: systemName)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(Text(label))
    }

    private func toolbarIcon(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(NativeTheme.textSecondary)
            .frame(width: 22, height: 22)
            .background(NativeTheme.elevated.opacity(0.75))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(NativeTheme.border, lineWidth: 1)
            }
    }

    private func masterInclusionSystemImage(for changes: [WorkspaceCommitChange]) -> String {
        let includedCount = includedCount(in: changes)
        if includedCount == 0 {
            return "square"
        }
        return areAllIncluded(in: changes) ? "checkmark.square.fill" : "minus.square.fill"
    }

    private func masterInclusionColor(for changes: [WorkspaceCommitChange]) -> Color {
        includedCount(in: changes) == 0 ? NativeTheme.textSecondary : NativeTheme.accent
    }

    private func includedCount(in changes: [WorkspaceCommitChange]) -> Int {
        changes.reduce(into: 0) { partialResult, change in
            if viewModel.includedPaths.contains(change.path) {
                partialResult += 1
            }
        }
    }

    private func areAllIncluded(in changes: [WorkspaceCommitChange]) -> Bool {
        guard !changes.isEmpty else {
            return false
        }
        return changes.allSatisfy { viewModel.includedPaths.contains($0.path) }
    }

    private func toggleSectionInclusion(for changes: [WorkspaceCommitChange]) {
        guard !changes.isEmpty else {
            return
        }
        let nextIncluded = !areAllIncluded(in: changes)
        for change in changes {
            viewModel.setInclusion(for: change.path, included: nextIncluded)
        }
    }

    private func fileNameText(for change: WorkspaceCommitChange) -> String {
        let fileName = (change.path as NSString).lastPathComponent
        return fileName.isEmpty ? change.path : fileName
    }

    private func fileNameColor(for change: WorkspaceCommitChange) -> Color {
        if viewModel.selectedChangePath == change.path {
            return NativeTheme.textPrimary
        }

        switch change.group {
        case .untracked:
            return NativeTheme.danger
        default:
            return NativeTheme.accent
        }
    }

    private func directoryText(for change: WorkspaceCommitChange) -> String? {
        var parts = [String]()
        let parentPath = (change.path as NSString).deletingLastPathComponent
        if !parentPath.isEmpty && parentPath != change.path {
            parts.append(parentPath)
        }

        switch change.status {
        case .renamed:
            if let oldPath = change.oldPath {
                parts.append("Renamed from \((oldPath as NSString).lastPathComponent)")
            }
        case .copied:
            if let oldPath = change.oldPath {
                parts.append("Copied from \((oldPath as NSString).lastPathComponent)")
            }
        case .unmerged:
            parts.append("Conflicted")
        default:
            break
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

}
