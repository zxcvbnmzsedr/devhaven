import SwiftUI
import AppKit
import DevHavenCore

private struct WorkspaceCommitRollbackSheetContext: Identifiable {
    let id = UUID()
    let changes: [WorkspaceCommitChange]
    let initialIncludedPaths: Set<String>
}

struct WorkspaceCommitChangesBrowserView: View {
    @Bindable var viewModel: WorkspaceCommitViewModel
    let onSyncDiffIfNeeded: (WorkspaceCommitChange) -> Void
    let onOpenDiff: (WorkspaceCommitChange) -> Void
    @State private var rollbackSheetContext: WorkspaceCommitRollbackSheetContext?
    @State private var collapsedRepositoryGroupIDs: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            if viewModel.isRevertingChanges {
                progressBanner(text: "正在还原变更…")
            } else if let message = browserErrorMessage {
                errorBanner(message: message)
            }

            Group {
                if viewModel.repositoryFamilies.count > 1 {
                    multiRepositoryChangesView
                } else if let snapshot = viewModel.changesSnapshot, !snapshot.changes.isEmpty {
                    let versionedChanges = snapshot.changes.filter { $0.group != .untracked }
                    let unversionedChanges = snapshot.changes.filter { $0.group == .untracked }

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if !versionedChanges.isEmpty {
                                section(
                                    title: "变更",
                                    changes: versionedChanges,
                                    repositoryGroupID: viewModel.repositoryContext.selectedRepositoryFamilyID
                                )
                            }

                            if !unversionedChanges.isEmpty {
                                section(
                                    title: "未跟踪文件",
                                    changes: unversionedChanges,
                                    repositoryGroupID: viewModel.repositoryContext.selectedRepositoryFamilyID
                                )
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
        .sheet(item: $rollbackSheetContext) { context in
            WorkspaceCommitRollbackSheet(
                executionPath: viewModel.repositoryContext.executionPath,
                changes: context.changes,
                initialIncludedPaths: context.initialIncludedPaths,
                onSubmit: { paths, deleteLocallyAddedFiles in
                    rollbackSheetContext = nil
                    viewModel.revertChanges(
                        paths: paths,
                        deleteLocallyAddedFiles: deleteLocallyAddedFiles
                    )
                },
                onClose: { rollbackSheetContext = nil }
            )
        }
    }

    @ViewBuilder
    private var multiRepositoryChangesView: some View {
        let visibleRepositoryGroups = viewModel.visibleRepositoryGroupSummaries
        let totalChangeCount = visibleRepositoryGroups.reduce(0) { $0 + $1.changeCount }
        if totalChangeCount == 0 {
            ContentUnavailableView(
                "暂无变更",
                systemImage: "checkmark.circle",
                description: Text("当前工作区下没有可提交变更。")
            )
            .foregroundStyle(NativeTheme.textSecondary)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(visibleRepositoryGroups) { summary in
                        repositoryGroupSection(summary)
                    }
                }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 4) {
            toolbarButton(systemName: "arrow.clockwise", label: "刷新变更") {
                viewModel.refreshChangesSnapshot()
            }
            .disabled(isInteractionDisabled)

            toolbarButton(
                systemName: viewModel.areAllChangesIncluded ? "checkmark.square.fill" : "checkmark.square",
                label: viewModel.areAllChangesIncluded ? "清空纳入" : "纳入全部"
            ) {
                viewModel.toggleAllInclusion()
            }
            .disabled(isInteractionDisabled || viewModel.changesSnapshot?.changes.isEmpty != false)

            toolbarButton(systemName: "arrow.uturn.backward", label: "还原…") {
                presentRollbackSheet(initialPaths: defaultRollbackSeedPaths)
            }
            .disabled(!viewModel.canRevert(paths: allChangePaths))

            toolbarButton(systemName: "scope", label: "定位到当前选中") {
                guard let path = viewModel.selectedChangePath ?? viewModel.changesSnapshot?.changes.first?.path else {
                    return
                }
                viewModel.selectChange(path)
            }
            .disabled(viewModel.changesSnapshot?.changes.isEmpty != false)

            Menu {
                Button("清除选中") {
                    viewModel.selectChange(nil)
                }
                .disabled(viewModel.selectedChangePath == nil)

                Button("刷新") {
                    viewModel.refreshChangesSnapshot()
                }
                .disabled(isInteractionDisabled)
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

    private func section(
        title: String,
        changes: [WorkspaceCommitChange],
        repositoryGroupID: String
    ) -> some View {
        Group {
            groupHeader(
                title: title,
                changes: changes,
                repositoryGroupID: repositoryGroupID
            )

            ForEach(changes) { change in
                changeRow(
                    change,
                    repositoryGroupID: repositoryGroupID,
                    executionPath: executionPath(forRepositoryGroupID: repositoryGroupID)
                )
            }
        }
    }

    private func repositoryGroupSection(_ summary: WorkspaceCommitRepositoryGroupSummary) -> some View {
        VStack(spacing: 0) {
            repositoryGroupHeader(summary)

            if isRepositoryGroupExpanded(summary.id),
               let snapshot = viewModel.changesSnapshot(forRepositoryGroupID: summary.id),
               !snapshot.changes.isEmpty {
                let versionedChanges = snapshot.changes.filter { $0.group != .untracked }
                let unversionedChanges = snapshot.changes.filter { $0.group == .untracked }

                if summary.isSelected {
                    if !versionedChanges.isEmpty {
                        section(
                            title: "变更",
                            changes: versionedChanges,
                            repositoryGroupID: summary.id
                        )
                    }
                    if !unversionedChanges.isEmpty {
                        section(
                            title: "未跟踪文件",
                            changes: unversionedChanges,
                            repositoryGroupID: summary.id
                        )
                    }
                } else {
                    if !versionedChanges.isEmpty {
                        previewSection(title: "变更", changes: versionedChanges, summary: summary)
                    }
                    if !unversionedChanges.isEmpty {
                        previewSection(title: "未跟踪文件", changes: unversionedChanges, summary: summary)
                    }
                }
            }
        }
    }

    private func repositoryGroupHeader(_ summary: WorkspaceCommitRepositoryGroupSummary) -> some View {
        let groupIncludedCount = includedCount(
            in: viewModel.changesSnapshot(forRepositoryGroupID: summary.id)?.changes ?? [],
            repositoryGroupID: summary.id
        )
        let groupAllIncluded = areAllIncluded(
            in: viewModel.changesSnapshot(forRepositoryGroupID: summary.id)?.changes ?? [],
            repositoryGroupID: summary.id
        )
        return HStack(spacing: 8) {
            Button {
                toggleRepositoryGroupExpansion(summary.id)
            } label: {
                Image(systemName: isRepositoryGroupExpanded(summary.id) ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NativeTheme.textSecondary)
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)

            Button {
                viewModel.selectRepositoryFamily(summary.id)
                collapsedRepositoryGroupIDs.remove(summary.id)
            } label: {
                HStack(spacing: 8) {
                    Text(summary.displayName)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(NativeTheme.textPrimary)

                    if let branchName = summary.branchName, !branchName.isEmpty {
                        Text(branchName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(NativeTheme.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(NativeTheme.elevated)
                            .clipShape(.capsule)
                    }

                    Text("\(summary.changeCount) 个文件")
                        .font(.caption)
                        .foregroundStyle(NativeTheme.textSecondary)

                    Spacer(minLength: 8)

                    Text("已纳入 \(groupIncludedCount)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(NativeTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                viewModel.toggleAllInclusion(for: summary.id)
            } label: {
                Image(systemName: groupAllIncluded ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(groupIncludedCount == 0 ? NativeTheme.textSecondary : NativeTheme.accent)
            }
            .buttonStyle(.plain)
            .disabled(isInteractionDisabled || summary.changeCount == 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(summary.isSelected ? NativeTheme.accent.opacity(0.10) : NativeTheme.window)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(NativeTheme.border)
                .frame(height: 1)
        }
    }

    private func previewSection(
        title: String,
        changes: [WorkspaceCommitChange],
        summary: WorkspaceCommitRepositoryGroupSummary
    ) -> some View {
        Group {
            groupHeader(
                title: title,
                changes: changes,
                repositoryGroupID: summary.id
            )

            ForEach(changes) { change in
                previewChangeRow(change, summary: summary)
            }
        }
    }

    private func groupHeader(
        title: String,
        changes: [WorkspaceCommitChange],
        repositoryGroupID: String
    ) -> some View {
        HStack(spacing: 8) {
            Button {
                toggleSectionInclusion(for: changes, repositoryGroupID: repositoryGroupID)
            } label: {
                Image(systemName: masterInclusionSystemImage(for: changes, repositoryGroupID: repositoryGroupID))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(masterInclusionColor(for: changes, repositoryGroupID: repositoryGroupID))
            }
            .buttonStyle(.plain)
            .disabled(isInteractionDisabled)

            Text("\(title) \(changes.count) 个文件")
                .font(.caption.weight(.semibold))
                .foregroundStyle(NativeTheme.textPrimary)

            Spacer(minLength: 8)

            Text("已纳入 \(includedCount(in: changes, repositoryGroupID: repositoryGroupID))")
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

    private func changeRow(
        _ change: WorkspaceCommitChange,
        repositoryGroupID: String,
        executionPath: String
    ) -> some View {
        HStack(spacing: 8) {
            Button {
                viewModel.toggleInclusion(for: change.path, repositoryGroupID: repositoryGroupID)
            } label: {
                Image(systemName: viewModel.isIncluded(change.path, repositoryGroupID: repositoryGroupID) ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(
                        viewModel.isIncluded(change.path, repositoryGroupID: repositoryGroupID)
                            ? NativeTheme.accent
                            : NativeTheme.textSecondary
                    )
            }
            .buttonStyle(.plain)
            .disabled(isInteractionDisabled)

            Image(nsImage: fileIcon(for: change, executionPath: executionPath))
                .resizable()
                .interpolation(.high)
                .frame(width: 16, height: 16)

            Button {
                viewModel.selectChange(change.path)
                onSyncDiffIfNeeded(change)
            } label: {
                HStack(spacing: 8) {
                    inlineTitleRow(change)
                    Spacer(minLength: 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    openChangeDiff(change)
                }
            )
            .contextMenu {
                Button("打开差异") {
                    openChangeDiff(change)
                }

                Button(viewModel.isIncluded(change.path, repositoryGroupID: repositoryGroupID) ? "从提交中移除" : "纳入提交") {
                    viewModel.toggleInclusion(for: change.path, repositoryGroupID: repositoryGroupID)
                }
                .disabled(isInteractionDisabled)

                Divider()

                Button("还原…", role: .destructive) {
                    presentRollbackSheet(initialPaths: [change.path])
                }
                .disabled(!viewModel.canRevert(paths: [change.path]))
            }
            .help("双击打开差异")
            .accessibilityAction(named: Text("打开差异")) {
                openChangeDiff(change)
            }
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
    }

    private func openChangeDiff(_ change: WorkspaceCommitChange) {
        viewModel.selectChange(change.path)
        onOpenDiff(change)
    }

    private func previewChangeRow(
        _ change: WorkspaceCommitChange,
        summary: WorkspaceCommitRepositoryGroupSummary
    ) -> some View {
        HStack(spacing: 8) {
            Button {
                viewModel.toggleInclusion(for: change.path, repositoryGroupID: summary.id)
            } label: {
                Image(systemName: viewModel.isIncluded(change.path, repositoryGroupID: summary.id) ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(
                        viewModel.isIncluded(change.path, repositoryGroupID: summary.id)
                            ? NativeTheme.accent
                            : NativeTheme.textSecondary
                    )
            }
            .buttonStyle(.plain)
            .disabled(isInteractionDisabled)

            Image(nsImage: fileIcon(for: change, executionPath: summary.executionPath))
                .resizable()
                .interpolation(.high)
                .frame(width: 16, height: 16)

            Button {
                activateRepositoryGroup(summary.id, selecting: change.path)
            } label: {
                HStack(spacing: 8) {
                    inlineTitleRow(change)
                    Spacer(minLength: 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    activateRepositoryGroup(summary.id, selecting: change.path)
                    onOpenDiff(change)
                }
            )
            .help("单击切换到该项目并选中文件，双击打开差异")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(NativeTheme.border.opacity(0.65))
                .frame(height: 1)
        }
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

    private func fileIcon(for change: WorkspaceCommitChange, executionPath: String) -> NSImage {
        let fileURL = URL(fileURLWithPath: executionPath, isDirectory: true)
            .appending(path: change.path)
        let icon = NSWorkspace.shared.icon(forFile: fileURL.path)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }

    private var isInteractionDisabled: Bool {
        viewModel.executionState.isRunning || viewModel.isRevertingChanges
    }

    private var allChangePaths: [String] {
        (viewModel.changesSnapshot?.changes ?? []).map(\.path)
    }

    private var includedChangePaths: [String] {
        (viewModel.changesSnapshot?.changes ?? [])
            .filter { viewModel.includedPaths.contains($0.path) }
            .map(\.path)
    }

    private var defaultRollbackSeedPaths: [String] {
        if let selectedPath = viewModel.selectedChangePath {
            return [selectedPath]
        }
        if !includedChangePaths.isEmpty {
            return includedChangePaths
        }
        return allChangePaths
    }

    private var browserErrorMessage: String? {
        let trimmed = viewModel.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func isRepositoryGroupExpanded(_ id: String) -> Bool {
        !collapsedRepositoryGroupIDs.contains(id)
    }

    private func toggleRepositoryGroupExpansion(_ id: String) {
        if collapsedRepositoryGroupIDs.contains(id) {
            collapsedRepositoryGroupIDs.remove(id)
        } else {
            collapsedRepositoryGroupIDs.insert(id)
        }
    }

    private func executionPath(forRepositoryGroupID id: String) -> String {
        viewModel.repositoryGroupSummaries.first(where: { $0.id == id })?.executionPath
            ?? viewModel.repositoryContext.executionPath
    }

    private func activateRepositoryGroup(_ id: String, selecting path: String? = nil) {
        viewModel.selectRepositoryFamily(id)
        collapsedRepositoryGroupIDs.remove(id)
        if let path {
            viewModel.selectChange(path)
            if let change = viewModel.changesSnapshot?.changes.first(where: { $0.path == path }) {
                onSyncDiffIfNeeded(change)
            }
        }
    }

    private func presentRollbackSheet(initialPaths: [String]) {
        guard let changes = viewModel.changesSnapshot?.changes, !changes.isEmpty else {
            return
        }
        let availablePaths = Set(changes.map(\.path))
        let seededPaths = Set(
            initialPaths
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        .intersection(availablePaths)
        guard !seededPaths.isEmpty else {
            return
        }
        rollbackSheetContext = WorkspaceCommitRollbackSheetContext(
            changes: changes,
            initialIncludedPaths: seededPaths
        )
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

    private func progressBanner(text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(.caption)
                .foregroundStyle(NativeTheme.textPrimary)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(NativeTheme.elevated)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(NativeTheme.border)
                .frame(height: 1)
        }
    }

    private func errorBanner(message: String) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
            Text(message)
                .font(.caption)
                .lineLimit(2)
            Spacer(minLength: 8)
        }
        .foregroundStyle(NativeTheme.warning)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(NativeTheme.warning.opacity(0.12))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(NativeTheme.border)
                .frame(height: 1)
        }
    }

    private func masterInclusionSystemImage(
        for changes: [WorkspaceCommitChange],
        repositoryGroupID: String
    ) -> String {
        let includedCount = includedCount(in: changes, repositoryGroupID: repositoryGroupID)
        if includedCount == 0 {
            return "square"
        }
        return areAllIncluded(in: changes, repositoryGroupID: repositoryGroupID)
            ? "checkmark.square.fill"
            : "minus.square.fill"
    }

    private func masterInclusionColor(
        for changes: [WorkspaceCommitChange],
        repositoryGroupID: String
    ) -> Color {
        includedCount(in: changes, repositoryGroupID: repositoryGroupID) == 0
            ? NativeTheme.textSecondary
            : NativeTheme.accent
    }

    private func includedCount(
        in changes: [WorkspaceCommitChange],
        repositoryGroupID: String
    ) -> Int {
        changes.reduce(into: 0) { partialResult, change in
            if viewModel.isIncluded(change.path, repositoryGroupID: repositoryGroupID) {
                partialResult += 1
            }
        }
    }

    private func areAllIncluded(
        in changes: [WorkspaceCommitChange],
        repositoryGroupID: String
    ) -> Bool {
        guard !changes.isEmpty else {
            return false
        }
        return changes.allSatisfy { viewModel.isIncluded($0.path, repositoryGroupID: repositoryGroupID) }
    }

    private func toggleSectionInclusion(
        for changes: [WorkspaceCommitChange],
        repositoryGroupID: String
    ) {
        guard !changes.isEmpty else {
            return
        }
        let nextIncluded = !areAllIncluded(in: changes, repositoryGroupID: repositoryGroupID)
        for change in changes {
            viewModel.setInclusion(
                for: change.path,
                repositoryGroupID: repositoryGroupID,
                included: nextIncluded
            )
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
