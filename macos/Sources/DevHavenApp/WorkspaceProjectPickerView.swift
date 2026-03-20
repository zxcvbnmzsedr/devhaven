import SwiftUI
import DevHavenCore

struct WorkspaceProjectPickerView: View {
    let projects: [Project]
    let onOpenProject: (String) -> Void
    let onClose: () -> Void

    @State private var searchQuery = ""

    private var filteredProjects: [Project] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return projects
        }
        return projects.filter { project in
            project.name.lowercased().contains(query)
                || project.path.lowercased().contains(query)
                || project.tags.contains(where: { $0.lowercased().contains(query) })
        }
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
                    description: Text("可以换个关键词继续搜索。")
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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(NativeTheme.surface)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(NativeTheme.textSecondary)
            TextField("搜索项目名称或路径...", text: $searchQuery)
                .textFieldStyle(.plain)
                .foregroundStyle(NativeTheme.textPrimary)
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
                Text(project.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(NativeTheme.textPrimary)
                    .lineLimit(1)
                Text(project.path)
                    .font(.caption)
                    .foregroundStyle(NativeTheme.textSecondary)
                    .lineLimit(1)
                if !project.tags.isEmpty {
                    Text(project.tags.joined(separator: " · "))
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
}
