import SwiftUI
import DevHavenCore

struct WorkspaceProjectListView: View {
    let projects: [Project]
    let activeProjectPath: String?
    let canOpenMoreProjects: Bool
    let onSelectProject: (String) -> Void
    let onOpenProjectPicker: () -> Void
    let onCloseProject: (String) -> Void
    let onExit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(projects) { project in
                        projectRow(project)
                    }
                }
                .padding(10)
            }
        }
        .background(NativeTheme.sidebar)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("已打开项目")
                .font(.caption.weight(.semibold))
                .foregroundStyle(NativeTheme.textSecondary)
            Spacer(minLength: 0)
            Button(action: onOpenProjectPicker) {
                Image(systemName: "plus")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(canOpenMoreProjects ? NativeTheme.textSecondary : NativeTheme.textSecondary.opacity(0.45))
                    .frame(width: 28, height: 28)
                    .background(NativeTheme.surface)
                    .clipShape(.rect(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(!canOpenMoreProjects)
            .help(canOpenMoreProjects ? "打开其他项目" : "没有更多可打开项目")
            Button("返回", action: onExit)
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(NativeTheme.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(NativeTheme.surface)
                .clipShape(.rect(cornerRadius: 8))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(NativeTheme.surface)
    }

    private func projectRow(_ project: Project) -> some View {
        let isActive = project.path == activeProjectPath
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(isActive ? NativeTheme.textPrimary : NativeTheme.textSecondary)
                    .lineLimit(1)
                Text(URL(fileURLWithPath: project.path).lastPathComponent)
                    .font(.caption2)
                    .foregroundStyle(NativeTheme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button {
                onCloseProject(project.path)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isActive ? NativeTheme.textPrimary : NativeTheme.textSecondary)
                    .frame(width: 22, height: 22)
                    .background(NativeTheme.surface)
                    .clipShape(.rect(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .help("关闭项目")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isActive ? NativeTheme.accent.opacity(0.18) : NativeTheme.elevated)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isActive ? NativeTheme.accent.opacity(0.7) : NativeTheme.border, lineWidth: 1)
        )
        .clipShape(.rect(cornerRadius: 10))
        .contentShape(.rect(cornerRadius: 10))
        .onTapGesture {
            onSelectProject(project.path)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .help(project.path)
    }
}
