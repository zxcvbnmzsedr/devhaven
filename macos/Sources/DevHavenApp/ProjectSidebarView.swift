import SwiftUI
import UniformTypeIdentifiers
import DevHavenCore

struct ProjectSidebarView: View {
    @Bindable var viewModel: NativeAppViewModel
    @State private var pendingDirectoryImportAction: ProjectDirectoryImportAction?
    @State private var isDirectoryImporterPresented = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                directorySection {
                    VStack(spacing: 6) {
                        ForEach(viewModel.directoryRows) { row in
                            if !row.isSystemEntry, let directoryPath = directoryPath(for: row) {
                                DirectoryRowView(
                                    row: row,
                                    isSelected: row.filter == viewModel.selectedDirectory,
                                    onSelect: { viewModel.selectDirectory(row.filter) },
                                    onOpenWorkspace: { viewModel.enterDirectoryWorkspace(directoryPath) },
                                    onRemove: {
                                        Task {
                                            do {
                                                try await viewModel.removeProjectDirectory(directoryPath)
                                            } catch {
                                                viewModel.errorMessage = error.localizedDescription
                                            }
                                        }
                                    }
                                )
                            } else {
                                sidebarRow(
                                    title: row.title,
                                    count: row.count,
                                    selected: row.filter == viewModel.selectedDirectory
                                ) {
                                    viewModel.selectDirectory(row.filter)
                                }
                            }
                        }
                    }
                }

                sidebarSection(title: "开发热力图", trailingSystemImage: nil) {
                    VStack(alignment: .leading, spacing: 12) {
                        if viewModel.isHeatmapFilterActive {
                            HStack(spacing: 8) {
                                Text("日期筛选已启用")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(NativeTheme.accent)
                                Spacer(minLength: 8)
                                Button("清除") {
                                    viewModel.clearHeatmapDateFilter()
                                }
                                .buttonStyle(.plain)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(NativeTheme.accent)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(NativeTheme.accent.opacity(0.12))
                            .clipShape(.rect(cornerRadius: 10))
                        }

                        if viewModel.sidebarHeatmapDays.isEmpty {
                            Text("暂无 Git 活跃度数据")
                                .font(.caption)
                                .foregroundStyle(NativeTheme.textSecondary)
                        } else {
                            GitHeatmapGridView(
                                days: viewModel.sidebarHeatmapDays,
                                style: .sidebar,
                                selectedDateKey: viewModel.selectedHeatmapDateKey,
                                onSelectDate: { dateKey in
                                    if let dateKey {
                                        viewModel.selectHeatmapDate(dateKey)
                                    } else {
                                        viewModel.clearHeatmapDateFilter()
                                    }
                                }
                            )
                        }

                        if let summary = viewModel.selectedHeatmapSummary {
                            Text(summary)
                                .font(.caption2)
                                .foregroundStyle(NativeTheme.textSecondary)
                        }

                        if viewModel.isHeatmapFilterActive {
                            if viewModel.heatmapActiveProjects.isEmpty {
                                Text("当天无活跃项目")
                                    .font(.caption)
                                    .foregroundStyle(NativeTheme.textSecondary)
                            } else {
                                VStack(spacing: 8) {
                                    ForEach(viewModel.heatmapActiveProjects) { item in
                                        Button {
                                            viewModel.selectProject(item.path)
                                        } label: {
                                            HStack(spacing: 10) {
                                                Text("\(item.commitCount)")
                                                    .font(.caption2.weight(.semibold))
                                                    .foregroundStyle(NativeTheme.accent)
                                                    .frame(minWidth: 28)
                                                    .padding(.vertical, 4)
                                                    .background(NativeTheme.accent.opacity(0.12))
                                                    .clipShape(.rect(cornerRadius: 8))

                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(item.name)
                                                        .font(.caption.weight(.semibold))
                                                        .foregroundStyle(NativeTheme.textPrimary)
                                                        .lineLimit(1)
                                                    Text(item.path)
                                                        .font(.caption2)
                                                        .foregroundStyle(NativeTheme.textSecondary)
                                                        .lineLimit(1)
                                                }
                                                Spacer(minLength: 0)
                                            }
                                            .padding(10)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(NativeTheme.elevated)
                                            .clipShape(.rect(cornerRadius: 10))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }

                sidebarSection(title: "CLI 会话", trailingSystemImage: "plus.circle", trailingAction: { viewModel.openQuickTerminal() }) {
                    if viewModel.cliSessionItems.isEmpty {
                        Text("暂无 CLI 会话，点击 + 开启快速终端")
                            .font(.caption)
                            .foregroundStyle(NativeTheme.textSecondary)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(viewModel.cliSessionItems) { item in
                                HStack(spacing: 8) {
                                    Button {
                                        viewModel.activateWorkspaceProject(item.projectPath)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack(alignment: .firstTextBaseline) {
                                                Circle()
                                                    .fill(NativeTheme.success)
                                                    .frame(width: 7, height: 7)
                                                Text(item.title)
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundStyle(NativeTheme.textPrimary)
                                                Spacer()
                                                Text(item.statusText)
                                                    .font(.caption2)
                                                    .foregroundStyle(NativeTheme.textSecondary)
                                            }
                                            Text(item.subtitle)
                                                .font(.caption2)
                                                .foregroundStyle(NativeTheme.textSecondary)
                                                .lineLimit(1)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(10)
                                        .background(NativeTheme.elevated)
                                        .clipShape(.rect(cornerRadius: 10))
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        viewModel.closeWorkspaceProject(item.projectPath)
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(NativeTheme.textSecondary)
                                            .frame(width: 26, height: 26)
                                            .background(NativeTheme.elevated)
                                            .clipShape(.rect(cornerRadius: 8))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                sidebarSection(title: "标签", trailingSystemImage: "plus.circle") {
                    VStack(spacing: 6) {
                        ForEach(viewModel.tagRows) { row in
                            sidebarRow(
                                title: row.title,
                                count: row.count,
                                selected: row.name == viewModel.selectedTag || (row.name == nil && viewModel.selectedTag == nil),
                                accentHex: row.colorHex
                            ) {
                                viewModel.selectTag(row.name)
                            }
                        }
                    }
                }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
            }
            recycleBinFooter
        }
        .fileImporter(
            isPresented: $isDirectoryImporterPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: pendingDirectoryImportAction == .addProjects,
            onCompletion: handleDirectoryImport
        )
    }

    private var recycleBinFooter: some View {
        VStack(spacing: 0) {
            Divider()

            Button {
                viewModel.revealRecycleBin()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "trash")
                        .font(.body)
                        .foregroundStyle(NativeTheme.textSecondary)
                    Text("回收站")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(NativeTheme.textPrimary)
                    Spacer(minLength: 8)
                    let recycleBinCount = viewModel.recycleBinItems.count
                    if recycleBinCount > 0 {
                        Text("\(recycleBinCount)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(NativeTheme.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.05))
                            .clipShape(.rect(cornerRadius: 6))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NativeTheme.surface)
            }
            .buttonStyle(.plain)
        }
    }

    private func directorySection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("目录")
                    .font(.headline)
                    .foregroundStyle(NativeTheme.textPrimary)
                Spacer()
                Menu {
                    Button("添加工作目录（扫描项目）") {
                        pendingDirectoryImportAction = .addDirectory
                        isDirectoryImporterPresented = true
                    }
                    Button("直接添加为项目") {
                        pendingDirectoryImportAction = .addProjects
                        isDirectoryImporterPresented = true
                    }
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.caption)
                        .foregroundStyle(NativeTheme.textSecondary)
                }
                .menuStyle(.borderlessButton)
                .focusable(false)
                .help("目录操作")
                .accessibilityLabel("目录操作")
            }
            content()
        }
    }

    private func sidebarSection<Content: View>(title: String, trailingSystemImage: String?, trailingAction: (() -> Void)? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(NativeTheme.textPrimary)
                Spacer()
                if let trailingSystemImage {
                    if let trailingAction {
                        Button(action: trailingAction) {
                            Image(systemName: trailingSystemImage)
                                .font(.caption)
                                .foregroundStyle(NativeTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Image(systemName: trailingSystemImage)
                            .font(.caption)
                            .foregroundStyle(NativeTheme.textSecondary)
                    }
                }
            }
            content()
        }
    }

    private func handleDirectoryImport(_ result: Result<[URL], Error>) {
        let action = pendingDirectoryImportAction
        pendingDirectoryImportAction = nil
        isDirectoryImporterPresented = false

        switch result {
        case let .success(urls):
            ProjectImportDiagnostics.shared.recordImporterCallback(
                action: action?.diagnosticsAction,
                urlCount: urls.count
            )
            Task { @MainActor in
                await ProjectDirectoryImportSupport.withSecurityScopedAccess(urls, action: action) {
                    guard let action else {
                        return
                    }
                    await ProjectDirectoryImportSupport.performImport(
                        urls: urls,
                        action: action,
                        viewModel: viewModel
                    )
                }
            }
        case let .failure(error):
            ProjectImportDiagnostics.shared.recordFailure(
                action: action?.diagnosticsAction,
                errorDescription: error.localizedDescription
            )
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func directoryPath(for row: NativeAppViewModel.DirectoryRow) -> String? {
        guard case let .directory(path) = row.filter else {
            return nil
        }
        return path
    }

    private func sidebarRow(title: String, count: Int, selected: Bool, accentHex: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let accentHex {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: accentHex) ?? NativeTheme.accent)
                        .frame(width: 6, height: 18)
                }
                Text(title)
                    .font(.callout)
                    .foregroundStyle(NativeTheme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(selected ? Color.white : NativeTheme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(selected ? NativeTheme.accent.opacity(0.85) : Color.white.opacity(0.05))
                    .clipShape(.rect(cornerRadius: 6))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? NativeTheme.accent.opacity(0.18) : Color.clear)
            .clipShape(.rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

private struct DirectoryRowView: View {
    let row: NativeAppViewModel.DirectoryRow
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpenWorkspace: () -> Void
    let onRemove: () -> Void

    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 10) {
                Text(row.title)
                    .font(.callout)
                    .foregroundStyle(NativeTheme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(row.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isSelected ? Color.white : NativeTheme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(isSelected ? NativeTheme.accent.opacity(0.85) : Color.white.opacity(0.05))
                    .clipShape(.rect(cornerRadius: 6))
                    .opacity(isHovering ? 0 : 1)
                    .animation(.easeInOut(duration: 0.15), value: isHovering)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? NativeTheme.accent.opacity(0.18) : Color.clear)
            .clipShape(.rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
            .onTapGesture(count: 2) {
                onSelect()
                onOpenWorkspace()
            }
            .onTapGesture {
                onSelect()
            }
            .help("单击筛选目录，双击进入目录工作区")

            Button(action: onRemove) {
                Image(systemName: "minus.circle")
                    .font(.caption)
                    .foregroundStyle(NativeTheme.textSecondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("移除此工作目录")
            .padding(.trailing, 10)
            .opacity(isHovering ? 1 : 0)
            .allowsHitTesting(isHovering)
            .animation(.easeInOut(duration: 0.15), value: isHovering)
        }
        .onHover { isHovering = $0 }
    }
}

private extension Color {
    init?(hex: String) {
        var normalized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("#") {
            normalized.removeFirst()
        }
        guard normalized.count == 6, let value = Int(normalized, radix: 16) else {
            return nil
        }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
