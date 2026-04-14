import AppKit
import SwiftUI
import DevHavenCore

struct WorkspaceGitHubIssueDetailView: View {
    @Bindable var viewModel: WorkspaceGitHubViewModel
    let detail: WorkspaceGitHubIssueDetail
    let onCreateIssueWorktree: ((WorkspaceGitHubIssueDetail) throws -> Void)?
    @State private var splitRatio = 0.68

    var body: some View {
        WorkspaceSplitView(
            direction: .horizontal,
            ratio: splitRatio,
            onRatioChange: { splitRatio = $0 },
            minLeadingSize: 360,
            minTrailingSize: 220,
            leading: {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        if let actionBanner {
                            feedbackBanner(
                                message: actionBanner.message,
                                tint: actionBanner.tint
                            )
                        }
                        actionsSection
                        bodySection
                        commentsSection
                    }
                    .padding(16)
                }
                .background(NativeTheme.window)
            },
            trailing: {
                WorkspaceGitHubDetailSidebarView {
                    WorkspaceGitHubDetailSidebarSection(title: "Assignees") {
                        WorkspaceGitHubActorListView(actors: detail.assignees)
                    }

                    WorkspaceGitHubDetailSidebarSection(title: "Labels") {
                        WorkspaceGitHubLabelListView(labels: detail.labels)
                    }

                    if let milestone = detail.milestone {
                        WorkspaceGitHubDetailSidebarSection(title: "Milestone") {
                            Text(milestone.title)
                                .font(.callout)
                                .foregroundStyle(NativeTheme.textPrimary)
                        }
                    }

                    WorkspaceGitHubDetailSidebarSection(title: "Details") {
                        VStack(alignment: .leading, spacing: 8) {
                            WorkspaceGitHubMetadataRow(title: "Created", value: gitHubAbsoluteDateText(detail.createdAt))
                            WorkspaceGitHubMetadataRow(title: "Updated", value: gitHubAbsoluteDateText(detail.updatedAt))
                            if let closedAt = detail.closedAt {
                                WorkspaceGitHubMetadataRow(title: "Closed", value: gitHubAbsoluteDateText(closedAt))
                            }
                            if detail.stateReason != .none {
                                WorkspaceGitHubMetadataRow(title: "Reason", value: gitHubIssueStateReasonTitle(detail.stateReason))
                            }
                            WorkspaceGitHubMetadataRow(title: "State", value: gitHubIssueStateTitle(detail.state, reason: detail.stateReason))
                            WorkspaceGitHubMetadataRow(title: "Comments", value: "\(detail.commentsCount)")
                        }
                    }
                }
            }
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(gitHubIssueStateColor(detail.state))
                    .frame(width: 12, height: 12)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 6) {
                    Text(detail.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(NativeTheme.textPrimary)
                    Text("#\(detail.number)")
                        .font(.callout)
                        .foregroundStyle(NativeTheme.textSecondary)
                    if let author = detail.author {
                        Text("作者：\(author.login ?? author.displayName)")
                            .font(.caption)
                            .foregroundStyle(NativeTheme.textSecondary)
                    }
                }

                Spacer(minLength: 0)

                Button("Open in GitHub") {
                    openURL(detail.url)
                }
                .buttonStyle(.borderedProminent)
                .tint(NativeTheme.accent)
            }
        }
        .padding(14)
        .background(NativeTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(NativeTheme.border, lineWidth: 1)
        )
        .clipShape(.rect(cornerRadius: 14))
    }

    private var actionsSection: some View {
        sectionCard(title: "Actions") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("建议分支")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NativeTheme.textSecondary)
                    Text(detail.suggestedBranchName)
                        .font(.callout.monospaced())
                        .foregroundStyle(NativeTheme.textPrimary)
                        .textSelection(.enabled)
                }

                HStack(spacing: 8) {
                    Button("创建并切换分支") {
                        viewModel.createAndCheckoutBranchForSelectedIssue()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isMutating)

                    Button("创建 worktree 并打开") {
                        do {
                            try onCreateIssueWorktree?(detail)
                            viewModel.reportExternalMutationSuccess(.createIssueWorktree)
                        } catch {
                            viewModel.reportMutationFailure(error)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isMutating || onCreateIssueWorktree == nil)
                }

                HStack(spacing: 8) {
                    switch detail.state {
                    case .open:
                        Button("关闭 Issue", role: .destructive) {
                            viewModel.closeSelectedIssue()
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.isMutating)
                    case .closed:
                        Button("重新打开 Issue") {
                            viewModel.reopenSelectedIssue()
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.isMutating)
                    case .unknown:
                        EmptyView()
                    }
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("新增评论")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NativeTheme.textSecondary)
                    TextEditor(text: $viewModel.issueCommentDraft)
                        .font(.callout)
                        .frame(minHeight: 108)
                        .padding(8)
                        .background(NativeTheme.elevated)
                        .clipShape(.rect(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(NativeTheme.border, lineWidth: 1)
                        )

                    HStack(spacing: 8) {
                        Spacer(minLength: 0)
                        Button("提交评论") {
                            viewModel.addCommentToSelectedIssue()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isMutating || viewModel.issueCommentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    private var bodySection: some View {
        sectionCard(title: "Description") {
            if (detail.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("暂无描述")
                    .font(.callout)
                    .foregroundStyle(NativeTheme.textSecondary)
            } else {
                Text(detail.body ?? "")
                    .font(.callout)
                    .foregroundStyle(NativeTheme.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var commentsSection: some View {
        sectionCard(title: "Comments") {
            if detail.comments.isEmpty {
                Text("暂无评论")
                    .font(.callout)
                    .foregroundStyle(NativeTheme.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(detail.comments) { comment in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Text(comment.author?.displayName ?? "Unknown")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(NativeTheme.textPrimary)
                                Text(gitHubRelativeDateText(comment.createdAt))
                                    .font(.caption)
                                    .foregroundStyle(NativeTheme.textSecondary)
                            }
                            Text(comment.body)
                                .font(.callout)
                                .foregroundStyle(NativeTheme.textPrimary)
                                .textSelection(.enabled)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(NativeTheme.elevated)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(NativeTheme.border, lineWidth: 1)
                        )
                        .clipShape(.rect(cornerRadius: 12))
                    }
                }
            }
        }
    }

    private var actionBanner: (message: String, tint: Color)? {
        if let mutationErrorMessage = viewModel.mutationErrorMessage,
           !mutationErrorMessage.isEmpty {
            return (mutationErrorMessage, NativeTheme.warning)
        }
        if let activeMutation = viewModel.activeMutation,
           viewModel.isMutating,
           isIssueMutation(activeMutation) {
            return (gitHubMutationStatusText(activeMutation), NativeTheme.accent)
        }
        if let lastSuccessfulMutation = viewModel.lastSuccessfulMutation,
           isIssueMutation(lastSuccessfulMutation) {
            return (gitHubMutationSuccessText(lastSuccessfulMutation), .green)
        }
        return nil
    }

    private func isIssueMutation(_ kind: WorkspaceGitHubMutationKind) -> Bool {
        switch kind {
        case .addIssueComment, .closeIssue, .reopenIssue, .createIssueBranch, .createIssueWorktree:
            return true
        default:
            return false
        }
    }

    private func feedbackBanner(message: String, tint: Color) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(tint)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.12))
            .clipShape(.rect(cornerRadius: 12))
    }

    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(NativeTheme.textPrimary)
            content()
        }
        .padding(14)
        .background(NativeTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(NativeTheme.border, lineWidth: 1)
        )
        .clipShape(.rect(cornerRadius: 14))
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
