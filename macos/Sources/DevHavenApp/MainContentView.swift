import SwiftUI
import AppKit
import DevHavenCore

struct MainContentView: View {
    @Bindable var viewModel: NativeAppViewModel

    private let listColumns = [
        GridItem(.flexible(minimum: 220), spacing: 14),
        GridItem(.flexible(minimum: 220), spacing: 14),
        GridItem(.flexible(minimum: 220), spacing: 14),
        GridItem(.flexible(minimum: 220), spacing: 14),
    ]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(NativeTheme.surface)

            if viewModel.filteredProjects.isEmpty {
                ContentUnavailableView(
                    "没有匹配项目",
                    systemImage: "magnifyingglass",
                    description: Text("可以调整搜索条件，或者切换目录 / 标签 / Git 筛选。")
                )
                .foregroundStyle(NativeTheme.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    if viewModel.projectListViewMode == .card {
                        LazyVGrid(columns: listColumns, spacing: 16) {
                            ForEach(viewModel.filteredProjects) { project in
                                projectCard(project)
                            }
                        }
                        .padding(18)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(viewModel.filteredProjects) { project in
                                projectRow(project)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 14)
                    }
                }
                .background(NativeTheme.window)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            toolbarIcon("waveform.path.ecg", action: { viewModel.revealDashboard() })
            toolbarIcon("square.split.2x1", action: { viewModel.closeDetailPanel() })
            toolbarIcon("gearshape", action: { viewModel.revealSettings() })

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(NativeTheme.textSecondary)
                TextField("搜索项目...", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .foregroundStyle(NativeTheme.textPrimary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(NativeTheme.elevated)
            .clipShape(.rect(cornerRadius: 10))
            .frame(maxWidth: 340)

            Spacer(minLength: 10)

            Menu {
                ForEach(NativeDateFilter.allCases) { filter in
                    Button(filter.title) {
                        viewModel.updateDateFilter(filter)
                    }
                }
            } label: {
                toolbarChip(viewModel.selectedDateFilter.title, systemImage: "calendar")
            }
            .menuStyle(.borderlessButton)

            Menu {
                ForEach(NativeGitFilter.allCases) { filter in
                    Button(filter.title) {
                        viewModel.updateGitFilter(filter)
                    }
                }
            } label: {
                toolbarChip(viewModel.selectedGitFilter.title, systemImage: "point.3.connected.trianglepath.dotted")
            }
            .menuStyle(.borderlessButton)

            Picker("视图模式", selection: Binding(
                get: { viewModel.projectListViewMode },
                set: { viewModel.updateProjectListViewMode($0) }
            )) {
                Label("卡片", systemImage: "square.grid.2x2.fill").tag(ProjectListViewMode.card)
                Label("列表", systemImage: "list.bullet").tag(ProjectListViewMode.list)
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
        }
    }

    private func projectCard(_ project: Project) -> some View {
        Button {
            viewModel.selectProject(project.path)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Text(project.name)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(NativeTheme.textPrimary)
                        .lineLimit(2)
                    Spacer(minLength: 10)
                    HStack(spacing: 10) {
                        cardActionIcon("folder") { openInFinder(project.path) }
                        cardActionIcon(viewModel.snapshot.appState.favoriteProjectPaths.contains(project.path) ? "star.fill" : "star") {
                            viewModel.toggleProjectFavorite(project.path)
                        }
                        cardActionIcon("trash") { viewModel.moveProjectToRecycleBin(project.path) }
                    }
                }

                Text("~/\(compactDisplayPath(project.path))")
                    .font(.caption)
                    .foregroundStyle(NativeTheme.textSecondary)
                    .lineLimit(1)

                HStack {
                    Label(dateString(project.mtime), systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(NativeTheme.textSecondary)
                    Spacer()
                    if project.gitCommits > 0 {
                        Text("\(project.gitCommits) 次提交")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(NativeTheme.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(NativeTheme.accent.opacity(0.14))
                            .clipShape(.rect(cornerRadius: 8))
                    } else {
                        Text("非 Git 项目")
                            .font(.caption)
                            .foregroundStyle(NativeTheme.textSecondary)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
            .background(NativeTheme.elevated)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(viewModel.selectedProjectPath == project.path && viewModel.isDetailPanelPresented ? NativeTheme.accent.opacity(0.8) : NativeTheme.border, lineWidth: 1)
            )
            .clipShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func projectRow(_ project: Project) -> some View {
        Button {
            viewModel.selectProject(project.path)
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                        .font(.headline)
                        .foregroundStyle(NativeTheme.textPrimary)
                    Text(project.path)
                        .font(.caption)
                        .foregroundStyle(NativeTheme.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(project.gitLastCommitMessage ?? "暂无提交摘要")
                    .font(.caption)
                    .foregroundStyle(NativeTheme.textSecondary)
                    .frame(maxWidth: 260, alignment: .leading)
                Text(dateString(project.mtime))
                    .font(.caption)
                    .foregroundStyle(NativeTheme.textSecondary)
                    .frame(width: 120, alignment: .leading)
                if project.gitCommits > 0 {
                    Text("\(project.gitCommits) 次提交")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(NativeTheme.accent)
                } else {
                    Text("非 Git")
                        .font(.caption2)
                        .foregroundStyle(NativeTheme.textSecondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(viewModel.selectedProjectPath == project.path && viewModel.isDetailPanelPresented ? NativeTheme.accent.opacity(0.12) : Color.clear)
            .clipShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func toolbarChip(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(.caption)
        .foregroundStyle(NativeTheme.textPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(NativeTheme.elevated)
        .clipShape(.rect(cornerRadius: 10))
    }

    private func toolbarIcon(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body)
                .foregroundStyle(NativeTheme.textSecondary)
                .frame(width: 32, height: 32)
                .background(NativeTheme.elevated)
                .clipShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    private func cardActionIcon(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.caption)
                .foregroundStyle(NativeTheme.textSecondary)
        }
        .buttonStyle(.plain)
    }

    private func compactDisplayPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return path.replacingOccurrences(of: home + "/", with: "")
        }
        return path
    }

    private func dateString(_ swiftDate: SwiftDate) -> String {
        guard let date = swiftDateToDate(swiftDate) else {
            return "--"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter.string(from: date)
    }

    private func openInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}
