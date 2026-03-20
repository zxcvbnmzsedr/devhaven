import SwiftUI
import DevHavenCore

struct WorkspaceProjectListView: View {
    let groups: [WorkspaceSidebarProjectGroup]
    let canOpenMoreProjects: Bool
    let onSelectProject: (String) -> Void
    let onOpenProjectPicker: () -> Void
    let onRequestCreateWorktree: (String) -> Void
    let onRefreshWorktrees: (String) -> Void
    let onOpenWorktree: (String, String) -> Void
    let onRetryWorktree: (String, String) -> Void
    let onRequestDeleteWorktree: (String, String) -> Void
    let onCloseProject: (String) -> Void
    let onExit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(groups) { group in
                        projectGroup(group)
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

    private func projectGroup(_ group: WorkspaceSidebarProjectGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    onSelectProject(group.rootProject.path)
                } label: {
                    projectRow(group)
                }
                .buttonStyle(.plain)

                HStack(spacing: 4) {
                    rowIconButton(systemName: "arrow.clockwise", help: "刷新 worktree") {
                        onRefreshWorktrees(group.rootProject.path)
                    }
                    rowIconButton(systemName: "plus", help: "创建或添加 worktree") {
                        onRequestCreateWorktree(group.rootProject.path)
                    }
                    rowIconButton(systemName: "xmark", help: "关闭项目") {
                        onCloseProject(group.rootProject.path)
                    }
                }
            }

            if !group.worktrees.isEmpty {
                VStack(spacing: 4) {
                    ForEach(group.worktrees) { worktree in
                        worktreeRow(worktree)
                    }
                }
                .padding(.leading, 12)
            }
        }
    }

    private func projectRow(_ group: WorkspaceSidebarProjectGroup) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(group.rootProject.name)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(group.isActive ? NativeTheme.textPrimary : NativeTheme.textSecondary)
                    .lineLimit(1)
                Text(URL(fileURLWithPath: group.rootProject.path).lastPathComponent)
                    .font(.caption2)
                    .foregroundStyle(NativeTheme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if !group.worktrees.isEmpty {
                Text("\(group.worktrees.count)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(group.isActive ? NativeTheme.textPrimary : NativeTheme.textSecondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(NativeTheme.surface)
                    .clipShape(.rect(cornerRadius: 7))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(group.isActive ? NativeTheme.accent.opacity(0.18) : NativeTheme.elevated)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(group.isActive ? NativeTheme.accent.opacity(0.7) : NativeTheme.border, lineWidth: 1)
        )
        .clipShape(.rect(cornerRadius: 10))
        .contentShape(.rect(cornerRadius: 10))
        .help(group.rootProject.path)
    }

    private func worktreeRow(_ item: WorkspaceSidebarWorktreeItem) -> some View {
        HStack(spacing: 8) {
            Button {
                if item.status == "failed" {
                    return
                }
                if item.status == "creating" {
                    return
                }
                onOpenWorktree(item.rootProjectPath, item.path)
            } label: {
                HStack(spacing: 8) {
                    Text("↳ \(item.name)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(item.isActive ? NativeTheme.textPrimary : NativeTheme.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(item.branch)
                        .font(.caption2.monospaced())
                        .foregroundStyle(NativeTheme.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(NativeTheme.surface)
                        .clipShape(.rect(cornerRadius: 6))
                    statusChip(item)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(item.isActive ? NativeTheme.accent.opacity(0.14) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(item.isActive ? NativeTheme.accent.opacity(0.55) : NativeTheme.border.opacity(0.6), lineWidth: 1)
                )
                .clipShape(.rect(cornerRadius: 8))
                .contentShape(.rect(cornerRadius: 8))
                .opacity(item.status == "creating" ? 0.8 : 1)
            }
            .buttonStyle(.plain)
            .disabled(item.status == "creating")

            if item.status == "failed" {
                rowTextButton(title: "重试", help: item.initError ?? "重试创建") {
                    onRetryWorktree(item.rootProjectPath, item.path)
                }
            }

            rowTextButton(title: "删除", help: "删除 worktree", foreground: NativeTheme.danger) {
                onRequestDeleteWorktree(item.rootProjectPath, item.path)
            }
            .disabled(item.status == "creating")
        }
        .help(item.path)
    }

    @ViewBuilder
    private func statusChip(_ item: WorkspaceSidebarWorktreeItem) -> some View {
        switch item.status {
        case "creating":
            Text("创建中")
                .font(.caption2.weight(.medium))
                .foregroundStyle(NativeTheme.warning)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(NativeTheme.warning.opacity(0.12))
                .clipShape(.rect(cornerRadius: 6))
        case "failed":
            Text("失败")
                .font(.caption2.weight(.medium))
                .foregroundStyle(NativeTheme.danger)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(NativeTheme.danger.opacity(0.12))
                .clipShape(.rect(cornerRadius: 6))
        default:
            EmptyView()
        }
    }

    private func rowIconButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(NativeTheme.textSecondary)
                .frame(width: 26, height: 26)
                .background(NativeTheme.surface)
                .clipShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(help)
    }

    private func rowTextButton(
        title: String,
        help: String,
        foreground: Color = NativeTheme.textSecondary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(foreground)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(NativeTheme.surface)
                .clipShape(.rect(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(help)
    }
}
