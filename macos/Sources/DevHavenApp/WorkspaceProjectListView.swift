import SwiftUI
import DevHavenCore

struct WorkspaceProjectListView: View {
    let groups: [WorkspaceSidebarProjectGroup]
    let canOpenMoreProjects: Bool
    let workspaceAlignmentGroups: [WorkspaceAlignmentGroupProjection]
    let workspaceAlignmentProjectOptions: [Project]
    let onSelectProject: (String) -> Void
    let onOpenWorkspaceAlignmentProject: (WorkspaceAlignmentMemberProjection) -> Void
    let onOpenProjectPicker: () -> Void
    let onRequestCreateWorktree: (String) -> Void
    let onRefreshWorktrees: (String) -> Void
    let onOpenWorktree: (String, String) -> Void
    let onRetryWorktree: (String, String) -> Void
    let onRequestDeleteWorktree: (String, String) -> Void
    let onFocusNotification: (WorkspaceTerminalNotification) -> Void
    let onCloseProject: (String) -> Void
    let onRequestCreateWorkspaceAlignment: (String?) -> Void
    let onOpenWorkspaceAlignment: (String) -> Void
    let onRequestEditWorkspaceAlignment: (String) -> Void
    let onRequestAddProjectsToWorkspaceAlignment: (String) -> Void
    let onRequestRecheckWorkspaceAlignment: (String) -> Void
    let onRequestApplyWorkspaceAlignment: (String) -> Void
    let onRequestDeleteWorkspaceAlignment: (String) -> Void
    let onRequestApplyWorkspaceAlignmentProject: (String, String) -> Void
    let onRequestRemoveWorkspaceAlignmentProject: (String, String) -> Void
    let onAddProjectToWorkspaceAlignment: (String, String) -> Void
    let onExit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(groups) { group in
                        ProjectGroupView(
                            group: group,
                            workspaceAlignmentGroups: workspaceAlignmentGroups,
                            onSelectProject: onSelectProject,
                            onRefreshWorktrees: onRefreshWorktrees,
                            onRequestCreateWorktree: onRequestCreateWorktree,
                            onCloseProject: onCloseProject,
                            onOpenWorktree: onOpenWorktree,
                            onRetryWorktree: onRetryWorktree,
                            onRequestDeleteWorktree: onRequestDeleteWorktree,
                            onFocusNotification: onFocusNotification,
                            onRequestCreateWorkspaceAlignmentFromProject: onRequestCreateWorkspaceAlignment,
                            onAddProjectToWorkspaceAlignment: onAddProjectToWorkspaceAlignment
                        )
                    }

                    Divider()
                        .padding(.vertical, 4)

                    WorkspaceAlignmentSectionView(
                        groups: workspaceAlignmentGroups,
                        onRequestCreateWorkspace: { onRequestCreateWorkspaceAlignment(nil) },
                        onOpenWorkspace: onOpenWorkspaceAlignment,
                        onRequestEditWorkspace: onRequestEditWorkspaceAlignment,
                        onRequestAddProjects: onRequestAddProjectsToWorkspaceAlignment,
                        onRequestRecheck: onRequestRecheckWorkspaceAlignment,
                        onRequestApply: onRequestApplyWorkspaceAlignment,
                        onRequestDelete: onRequestDeleteWorkspaceAlignment,
                        onOpenProject: onOpenWorkspaceAlignmentProject,
                        onRequestApplyProject: onRequestApplyWorkspaceAlignmentProject,
                        onRequestRemoveProject: onRequestRemoveWorkspaceAlignmentProject
                    )
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
    let workspaceAlignmentGroups: [WorkspaceAlignmentGroupProjection]
    let onSelectProject: (String) -> Void
    let onRefreshWorktrees: (String) -> Void
    let onRequestCreateWorktree: (String) -> Void
    let onCloseProject: (String) -> Void
    let onOpenWorktree: (String, String) -> Void
    let onRetryWorktree: (String, String) -> Void
    let onRequestDeleteWorktree: (String, String) -> Void
    let onFocusNotification: (WorkspaceTerminalNotification) -> Void
    let onRequestCreateWorkspaceAlignmentFromProject: (String?) -> Void
    let onAddProjectToWorkspaceAlignment: (String, String) -> Void

    @State private var isHovering = false

    private var cardBg: Color {
        group.isActive ? NativeTheme.accent.opacity(0.12) : NativeTheme.elevated
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button {
                    onSelectProject(group.rootProject.path)
                } label: {
                    projectMainContent
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect(cornerRadius: 10))

                HStack(spacing: 4) {
                    groupStatusAccessory

                    HStack(spacing: 4) {
                        if !group.rootProject.isTransientWorkspaceProject {
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
                    .allowsHitTesting(isHovering)
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBg)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(group.isActive ? NativeTheme.accent.opacity(0.5) : NativeTheme.border.opacity(0.5), lineWidth: 1)
            )
            .clipShape(.rect(cornerRadius: 10))
            .contentShape(.rect(cornerRadius: 10))
            .help(group.rootProject.path)
            .onHover { isHovering = $0 }
            .contextMenu {
                if !group.rootProject.isTransientWorkspaceProject {
                    Button("基于当前项目新建工作区…") {
                        onRequestCreateWorkspaceAlignmentFromProject(group.rootProject.path)
                    }
                    if !workspaceAlignmentGroups.isEmpty {
                        Divider()
                        ForEach(workspaceAlignmentGroups) { workspace in
                            Button("添加到「\(workspace.definition.name)」") {
                                onAddProjectToWorkspaceAlignment(group.rootProject.path, workspace.id)
                            }
                        }
                    }
                }
            }

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

    private var projectMainContent: some View {
        let dirName = URL(fileURLWithPath: group.rootProject.path).lastPathComponent
        let showSubtitle = dirName != group.rootProject.name
        let agentAccessory = WorkspaceAgentStatusAccessory(agentState: group.agentState, agentKind: group.agentKind)

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
                if let branch = group.currentBranch, !group.rootProject.isTransientWorkspaceProject {
                    Text(branch)
                        .font(.caption2.monospaced())
                        .foregroundStyle(NativeTheme.textSecondary.opacity(0.7))
                        .lineLimit(1)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(NativeTheme.surface.opacity(0.8))
                        .clipShape(.rect(cornerRadius: 5))
                }
                if let agentAccessory {
                    Text(
                        displayedAgentSummaryText(
                            label: agentAccessory.label,
                            summary: group.agentSummary
                        )
                        .map { "\(agentAccessory.label)：\($0)" } ?? agentAccessory.label
                    )
                        .font(.caption2)
                        .foregroundStyle(agentAccessoryColor(agentAccessory).opacity(0.9))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect(cornerRadius: 10))
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
        } else if let agentAccessory = WorkspaceAgentStatusAccessory(agentState: group.agentState, agentKind: group.agentKind) {
            Image(systemName: agentAccessory.symbolName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(agentAccessoryColor(agentAccessory))
                .frame(width: 24, height: 24)
                .background(NativeTheme.surface.opacity(0.8))
                .clipShape(.rect(cornerRadius: 7))
                .help(agentAccessoryTooltip(accessory: agentAccessory, summary: group.agentSummary))
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

    private func agentAccessoryColor(_ accessory: WorkspaceAgentStatusAccessory) -> Color {
        switch accessory.state {
        case .waiting:
            NativeTheme.warning
        case .failed:
            NativeTheme.danger
        case .running, .completed:
            NativeTheme.accent
        case .idle, .unknown:
            NativeTheme.textSecondary
        }
    }

    private func agentAccessoryTooltip(accessory: WorkspaceAgentStatusAccessory, summary: String?) -> String {
        guard let summary = displayedAgentSummaryText(label: accessory.label, summary: summary) else {
            return accessory.label
        }
        return "\(accessory.label)\n\(summary)"
    }

    private func displayedAgentSummaryText(label: String, summary: String?) -> String? {
        let trimmedSummary = summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedSummary.isEmpty else {
            return nil
        }
        guard trimmedSummary != label else {
            return nil
        }
        return trimmedSummary
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
        HStack(spacing: 6) {
            Button {
                guard item.displayState == .normal else { return }
                onOpenWorktree(item.rootProjectPath, item.path)
            } label: {
                rowMainContent
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect(cornerRadius: 7))
            .disabled({
                if case .creating = item.displayState { return true }
                return false
            }())

            HStack(spacing: 4) {
                if case .failed = item.displayState {
                    actionChip(title: "重试", help: item.initError ?? "重试创建") {
                        onRetryWorktree(item.rootProjectPath, item.path)
                    }
                }
                actionChip(title: "删除", help: "删除 worktree") {
                    onRequestDeleteWorktree(item.rootProjectPath, item.path)
                }
            }
            .allowsHitTesting(isHovering && {
                if case .creating = item.displayState { return false }
                return true
            }())
            .opacity(isHovering && {
                if case .creating = item.displayState { return false }
                return true
            }() ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: isHovering)
            .padding(.trailing, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onHover { isHovering = $0 }
        .help(item.path)
        .background(item.isActive ? NativeTheme.accent.opacity(0.1) : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(item.isActive ? NativeTheme.accent.opacity(0.4) : NativeTheme.border.opacity(0.4), lineWidth: 1)
        )
        .clipShape(.rect(cornerRadius: 7))
        .contentShape(.rect(cornerRadius: 7))
        .opacity({
            if case .creating = item.displayState { return 0.7 }
            return 1.0
        }())
    }

    private var rowMainContent: some View {
        let agentAccessory = WorkspaceAgentStatusAccessory(agentState: item.agentState, agentKind: item.agentKind)
        return HStack(spacing: 6) {
            Image(systemName: "arrow.turn.down.right")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(NativeTheme.textSecondary.opacity(0.5))
            if let agentAccessory {
                Image(systemName: agentAccessory.symbolName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(agentAccessoryColor(agentAccessory))
                    .frame(width: 16, height: 16)
                    .help(agentAccessoryTooltip(accessory: agentAccessory, summary: item.agentSummary))
            } else if item.taskStatus == .running {
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
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(item.isActive ? NativeTheme.textPrimary : NativeTheme.textSecondary)
                    .lineLimit(1)
                if let agentAccessory,
                   let text = displayedWorktreeAgentText(label: agentAccessory.label, summary: item.agentSummary) {
                    Text(text)
                        .font(.caption2)
                        .foregroundStyle(agentAccessoryColor(agentAccessory).opacity(0.9))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Text(item.branch)
                .font(.caption2.monospaced())
                .foregroundStyle(NativeTheme.textSecondary.opacity(0.7))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(NativeTheme.surface.opacity(0.8))
                .clipShape(.rect(cornerRadius: 5))
            statusChip
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect(cornerRadius: 7))
    }

    @ViewBuilder
    private var statusChip: some View {
        switch item.displayState {
        case .creating:
            Text("创建中")
                .font(.caption2.weight(.medium))
                .foregroundStyle(NativeTheme.warning)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(NativeTheme.warning.opacity(0.12))
                .clipShape(.rect(cornerRadius: 6))
        case .failed:
            Text("失败")
                .font(.caption2.weight(.medium))
                .foregroundStyle(NativeTheme.danger)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(NativeTheme.danger.opacity(0.12))
                .clipShape(.rect(cornerRadius: 6))
        case .normal:
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

    private func agentAccessoryColor(_ accessory: WorkspaceAgentStatusAccessory) -> Color {
        switch accessory.state {
        case .waiting:
            NativeTheme.warning
        case .failed:
            NativeTheme.danger
        case .running, .completed:
            NativeTheme.accent
        case .idle, .unknown:
            NativeTheme.textSecondary
        }
    }

    private func agentAccessoryTooltip(accessory: WorkspaceAgentStatusAccessory, summary: String?) -> String {
        guard let summary = displayedAgentSummaryText(label: accessory.label, summary: summary) else {
            return accessory.label
        }
        return "\(accessory.label)\n\(summary)"
    }

    private func displayedWorktreeAgentText(label: String, summary: String?) -> String? {
        displayedAgentSummaryText(label: label, summary: summary)
            .map { "\(label)：\($0)" } ?? label
    }

    private func displayedAgentSummaryText(label: String, summary: String?) -> String? {
        let trimmedSummary = summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedSummary.isEmpty else {
            return nil
        }
        guard trimmedSummary != label else {
            return nil
        }
        return trimmedSummary
    }
}
