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
    let onFocusNotification: (WorkspaceTerminalNotification) -> Void
    let onCloseProject: (String) -> Void
    let onExit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(groups) { group in
                        ProjectGroupView(
                            group: group,
                            onSelectProject: onSelectProject,
                            onRefreshWorktrees: onRefreshWorktrees,
                            onRequestCreateWorktree: onRequestCreateWorktree,
                            onCloseProject: onCloseProject,
                            onOpenWorktree: onOpenWorktree,
                            onRetryWorktree: onRetryWorktree,
                            onRequestDeleteWorktree: onRequestDeleteWorktree,
                            onFocusNotification: onFocusNotification
                        )
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
}

// MARK: - Project Group Row

private struct ProjectGroupView: View {
    let group: WorkspaceSidebarProjectGroup
    let onSelectProject: (String) -> Void
    let onRefreshWorktrees: (String) -> Void
    let onRequestCreateWorktree: (String) -> Void
    let onCloseProject: (String) -> Void
    let onOpenWorktree: (String, String) -> Void
    let onRetryWorktree: (String, String) -> Void
    let onRequestDeleteWorktree: (String, String) -> Void
    let onFocusNotification: (WorkspaceTerminalNotification) -> Void

    @State private var isHovering = false

    private var cardBg: Color {
        group.isActive ? NativeTheme.accent.opacity(0.12) : NativeTheme.elevated
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                onSelectProject(group.rootProject.path)
            } label: {
                projectCard
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }

            if !group.worktrees.isEmpty {
                VStack(spacing: 4) {
                    ForEach(group.worktrees) { worktree in
                        WorktreeRowView(
                            item: worktree,
                            onOpenWorktree: onOpenWorktree,
                            onRetryWorktree: onRetryWorktree,
                            onRequestDeleteWorktree: onRequestDeleteWorktree,
                            onFocusNotification: onFocusNotification
                        )
                    }
                }
                .padding(.leading, 12)
            }
        }
    }

    private var projectCard: some View {
        let dirName = URL(fileURLWithPath: group.rootProject.path).lastPathComponent
        let showSubtitle = dirName != group.rootProject.name

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(group.rootProject.name)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(group.isActive ? NativeTheme.textPrimary : NativeTheme.textSecondary)
                    .lineLimit(1)
                if showSubtitle {
                    Text(dirName)
                        .font(.caption2)
                        .foregroundStyle(NativeTheme.textSecondary.opacity(0.7))
                        .lineLimit(1)
                }
                if let branch = group.currentBranch, !group.rootProject.isQuickTerminal {
                    Text(branch)
                        .font(.caption2.monospaced())
                        .foregroundStyle(NativeTheme.textSecondary.opacity(0.7))
                        .lineLimit(1)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(NativeTheme.surface.opacity(0.8))
                        .clipShape(.rect(cornerRadius: 5))
                }
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBg)
        .overlay(alignment: .trailing) {
            HStack(spacing: 4) {
                groupStatusAccessory

                HStack(spacing: 4) {
                    if !group.rootProject.isQuickTerminal {
                        iconButton(systemName: "arrow.clockwise", help: "刷新 worktree") {
                            onRefreshWorktrees(group.rootProject.path)
                        }
                        iconButton(systemName: "plus", help: "创建或添加 worktree") {
                            onRequestCreateWorktree(group.rootProject.path)
                        }
                    }
                    iconButton(systemName: "xmark", help: "关闭项目") {
                        onCloseProject(group.rootProject.path)
                    }
                }
                .opacity(isHovering ? 1 : 0)
                .animation(.easeInOut(duration: 0.15), value: isHovering)
            }
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .background(
                LinearGradient(
                    colors: [cardBg.opacity(0), cardBg, cardBg],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(group.isActive ? NativeTheme.accent.opacity(0.5) : NativeTheme.border.opacity(0.5), lineWidth: 1)
        )
        .clipShape(.rect(cornerRadius: 10))
        .contentShape(.rect(cornerRadius: 10))
        .help(group.rootProject.path)
    }

    @ViewBuilder
    private var groupStatusAccessory: some View {
        if group.hasUnreadNotifications {
            WorkspaceNotificationPopoverButton(
                notifications: group.notifications,
                onFocusNotification: onFocusNotification
            ) {
                badgeButton(systemName: "bell.fill", value: group.unreadNotificationCount)
            }
        } else if group.taskStatus == .running {
            ProgressView()
                .controlSize(.small)
                .frame(width: 24, height: 24)
        }
    }

    private func badgeButton(systemName: String, value: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: systemName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(NativeTheme.warning)
                .frame(width: 24, height: 24)
                .background(NativeTheme.surface.opacity(0.8))
                .clipShape(.rect(cornerRadius: 7))

            if value > 0 {
                Text("\(value)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(NativeTheme.warning)
                    .clipShape(.capsule)
                    .offset(x: 6, y: -6)
            }
        }
    }

    private func iconButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(NativeTheme.textSecondary)
                .frame(width: 24, height: 24)
                .background(NativeTheme.surface.opacity(0.8))
                .clipShape(.rect(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(help)
    }
}

// MARK: - Worktree Row

private struct WorktreeRowView: View {
    let item: WorkspaceSidebarWorktreeItem
    let onOpenWorktree: (String, String) -> Void
    let onRetryWorktree: (String, String) -> Void
    let onRequestDeleteWorktree: (String, String) -> Void
    let onFocusNotification: (WorkspaceTerminalNotification) -> Void

    @State private var isHovering = false

    var body: some View {
        Button {
            if item.status == "failed" || item.status == "creating" { return }
            onOpenWorktree(item.rootProjectPath, item.path)
        } label: {
            rowContent
        }
        .buttonStyle(.plain)
        .disabled(item.status == "creating")
        .onHover { isHovering = $0 }
        .help(item.path)
    }

    private var rowContent: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.turn.down.right")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(NativeTheme.textSecondary.opacity(0.5))
            if item.taskStatus == .running {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 14, height: 14)
            } else if item.hasUnreadNotifications {
                WorkspaceNotificationPopoverButton(
                    notifications: item.notifications,
                    onFocusNotification: onFocusNotification
                ) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(NativeTheme.warning)
                            .frame(width: 16, height: 16)
                        if item.unreadNotificationCount > 0 {
                            Circle()
                                .fill(NativeTheme.warning)
                                .frame(width: 6, height: 6)
                                .offset(x: 2, y: -2)
                        }
                    }
                }
            }
            Text(item.name)
                .font(.caption.weight(.medium))
                .foregroundStyle(item.isActive ? NativeTheme.textPrimary : NativeTheme.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if item.branch != item.name {
                Text(item.branch)
                    .font(.caption2.monospaced())
                    .foregroundStyle(NativeTheme.textSecondary.opacity(0.7))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(NativeTheme.surface.opacity(0.8))
                    .clipShape(.rect(cornerRadius: 5))
            }
            statusChip
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(item.isActive ? NativeTheme.accent.opacity(0.1) : Color.clear)
        .overlay(alignment: .trailing) {
            // 删除/重试按钮覆盖在行右侧
            HStack(spacing: 4) {
                if item.status == "failed" {
                    actionChip(title: "重试", help: item.initError ?? "重试创建") {
                        onRetryWorktree(item.rootProjectPath, item.path)
                    }
                }
                actionChip(title: "删除", help: "删除 worktree") {
                    onRequestDeleteWorktree(item.rootProjectPath, item.path)
                }
            }
            .padding(.trailing, 6)
            .opacity(isHovering && item.status != "creating" ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: isHovering)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(item.isActive ? NativeTheme.accent.opacity(0.4) : NativeTheme.border.opacity(0.4), lineWidth: 1)
        )
        .clipShape(.rect(cornerRadius: 7))
        .contentShape(.rect(cornerRadius: 7))
        .opacity(item.status == "creating" ? 0.7 : 1)
    }

    @ViewBuilder
    private var statusChip: some View {
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

    private func actionChip(title: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(NativeTheme.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(NativeTheme.surface)
                .clipShape(.rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(help)
    }
}
