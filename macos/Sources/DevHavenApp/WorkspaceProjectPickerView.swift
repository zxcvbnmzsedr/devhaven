import SwiftUI
import DevHavenCore

struct WorkspaceProjectPickerView: View {
    let projects: [Project]
    let onOpenProject: (String) -> Void
    let onClose: () -> Void

    @State private var searchQuery = ""
    @FocusState private var isSearchFieldFocused: Bool

    private var filteredProjects: [Project] {
        projects.filter { workspaceProjectPickerMatchesSearch($0, query: searchQuery) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField

            if projects.isEmpty {
                ContentUnavailableView(
                    "没有可打开项目",
                    systemImage: "plus.square.on.square",
                    description: Text("当前可见项目都已经在左侧已打开列表中了。")
                )
                .foregroundStyle(NativeTheme.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredProjects.isEmpty {
                ContentUnavailableView(
                    "没有匹配项目",
                    systemImage: "magnifyingglass",
                    description: Text("可以搜索项目名 / 路径 / 备注 / 标签，或者换个关键词继续搜索。")
                )
                .foregroundStyle(NativeTheme.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredProjects) { project in
                            Button {
                                onOpenProject(project.path)
                            } label: {
                                projectRow(project)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(14)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 460)
        .background(NativeTheme.window)
        .onAppear {
            requestInitialSearchFocus()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("打开项目")
                    .font(.headline)
                    .foregroundStyle(NativeTheme.textPrimary)
                Text("把更多项目加入左侧已打开列表。")
                    .font(.caption)
                    .foregroundStyle(NativeTheme.textSecondary)
            }
            Spacer(minLength: 0)
            Button("关闭", action: onClose)
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(NativeTheme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(NativeTheme.surface)
                .clipShape(.rect(cornerRadius: 8))
                .focusable(false)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(NativeTheme.surface)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(NativeTheme.textSecondary)
            TextField("搜索项目名称、路径或备注...", text: $searchQuery)
                .textFieldStyle(.plain)
                .foregroundStyle(NativeTheme.textPrimary)
                .focused($isSearchFieldFocused)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(NativeTheme.elevated)
        .clipShape(.rect(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func projectRow(_ project: Project) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(projectSearchHighlightedText(project.name, query: searchQuery))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(NativeTheme.textPrimary)
                    .lineLimit(1)
                Text(projectSearchHighlightedText(project.path, query: searchQuery))
                    .font(.caption)
                    .foregroundStyle(NativeTheme.textSecondary)
                    .lineLimit(1)
                if let notesSummary = project.notesSummary,
                   !notesSummary.isEmpty {
                    Text(projectSearchHighlightedText(notesSummary, query: searchQuery))
                        .font(.caption)
                        .foregroundStyle(NativeTheme.textPrimary.opacity(0.82))
                        .lineLimit(1)
                }
                if !project.tags.isEmpty {
                    Text(projectSearchHighlightedText(project.tags.joined(separator: " · "), query: searchQuery))
                        .font(.caption2)
                        .foregroundStyle(NativeTheme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "plus.circle.fill")
                .font(.body)
                .foregroundStyle(NativeTheme.accent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NativeTheme.elevated)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(NativeTheme.border, lineWidth: 1)
        )
        .clipShape(.rect(cornerRadius: 12))
        .contentShape(.rect(cornerRadius: 12))
        .help(project.path)
    }

    private func requestInitialSearchFocus() {
        DispatchQueue.main.async {
            isSearchFieldFocused = true
        }
    }
}

func workspaceProjectPickerMatchesSearch(
    _ project: Project,
    query: String
) -> Bool {
    let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !normalizedQuery.isEmpty else {
        return true
    }

    return project.name.lowercased().contains(normalizedQuery)
        || project.path.lowercased().contains(normalizedQuery)
        || (project.notesSummary?.lowercased().contains(normalizedQuery) ?? false)
        || project.tags.contains(where: { $0.lowercased().contains(normalizedQuery) })
}
