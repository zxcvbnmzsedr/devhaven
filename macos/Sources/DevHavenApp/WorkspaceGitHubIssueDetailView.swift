import AppKit
import SwiftUI
import DevHavenCore

struct WorkspaceGitHubIssueDetailView: View {
    @Bindable var viewModel: WorkspaceGitHubViewModel
    let detail: WorkspaceGitHubIssueDetail
    let onCreateIssueWorktree: ((WorkspaceGitHubIssueDetail) throws -> Void)?
    @State private var splitRatio = 0.72

    var body: some View {
        WorkspaceSplitView(
            direction: .horizontal,
            ratio: splitRatio,
            onRatioChange: { splitRatio = $0 },
            minLeadingSize: 420,
            minTrailingSize: 260,
            leading: {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header

                        if let actionBanner {
                            feedbackBanner(
                                message: actionBanner.message,
                                tint: actionBanner.tint
                            )
                        }

                        conversationSection
                        commentComposerSection
                    }
                    .padding(18)
                }
                .background(NativeTheme.window)
            },
            trailing: {
                WorkspaceGitHubDetailSidebarView {
                    statusSection
                    developmentSection

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
                            WorkspaceGitHubMetadataRow(title: "Comments", value: "\(detail.commentsCount)")
                        }
                    }
                }
            }
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(detail.title)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(NativeTheme.textPrimary)

                        Text("#\(detail.number)")
                            .font(.title3)
                            .foregroundStyle(NativeTheme.textSecondary)
                    }

                    HStack(alignment: .center, spacing: 10) {
                        issueStateBadge

                        Text(issueActivitySummary)
                            .font(.callout)
                            .foregroundStyle(NativeTheme.textSecondary)
                            .lineLimit(2)
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
        .padding(16)
        .background(NativeTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(NativeTheme.border, lineWidth: 1)
        )
        .clipShape(.rect(cornerRadius: 14))
    }

    private var conversationSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Conversation")
                .font(.headline)
                .foregroundStyle(NativeTheme.textPrimary)

            timelineEntry(
                iconSystemName: gitHubIssueStateSymbolName(detail.state),
                iconTint: gitHubIssueStateColor(detail.state),
                authorText: gitHubActorSummaryText(detail.author) ?? "未知用户",
                headline: "opened this issue \(gitHubRelativeDateText(detail.createdAt))",
                bodyText: trimmedBodyText ?? "暂无描述"
            )

            if detail.comments.isEmpty {
                Text("暂无后续评论")
                    .font(.callout)
                    .foregroundStyle(NativeTheme.textSecondary)
                    .padding(.leading, 40)
            } else {
                ForEach(detail.comments) { comment in
                    timelineEntry(
                        iconSystemName: "text.bubble.fill",
                        iconTint: NativeTheme.accent,
                        authorText: gitHubActorSummaryText(comment.author) ?? "未知用户",
                        headline: "commented \(gitHubRelativeDateText(comment.createdAt))",
                        bodyText: comment.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "空评论" : comment.body
                    )
                }
            }
        }
    }

    private var commentComposerSection: some View {
        sectionCard(title: "Add a comment") {
            VStack(alignment: .leading, spacing: 10) {
                TextEditor(text: $viewModel.issueCommentDraft)
                    .font(.callout)
                    .frame(minHeight: 120)
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
                    .disabled(viewModel.isMutating || trimmedCommentDraft == nil)
                }
            }
        }
    }

    private var statusSection: some View {
        WorkspaceGitHubDetailSidebarSection(title: "Status") {
            VStack(alignment: .leading, spacing: 12) {
                issueStateBadge

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
            }
        }
    }

    private var developmentSection: some View {
        WorkspaceGitHubDetailSidebarSection(title: "Development") {
            VStack(alignment: .leading, spacing: 10) {
                Text("建议分支")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NativeTheme.textSecondary)

                Text(detail.suggestedBranchName)
                    .font(.callout.monospaced())
                    .foregroundStyle(NativeTheme.textPrimary)
                    .textSelection(.enabled)

                VStack(alignment: .leading, spacing: 8) {
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
            }
        }
    }

    private var issueStateBadge: some View {
        let tint = gitHubIssueStateColor(detail.state)
        return HStack(spacing: 6) {
            Image(systemName: gitHubIssueStateSymbolName(detail.state))
                .font(.system(size: 12, weight: .semibold))
            Text(gitHubIssueStateTitle(detail.state, reason: detail.stateReason))
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.12))
        .overlay(
            Capsule()
                .stroke(tint.opacity(0.32), lineWidth: 1)
        )
        .clipShape(.capsule)
    }

    private var issueActivitySummary: String {
        let authorText = gitHubActorSummaryText(detail.author) ?? "未知用户"
        let openedText = "opened \(gitHubRelativeDateText(detail.createdAt))"
        switch detail.state {
        case .open:
            return "\(authorText) \(openedText) · \(detail.commentsCount) comments"
        case .closed:
            if let closedAt = detail.closedAt {
                return "\(authorText) \(openedText) · closed \(gitHubRelativeDateText(closedAt)) · \(detail.commentsCount) comments"
            }
            return "\(authorText) \(openedText) · updated \(gitHubRelativeDateText(detail.updatedAt)) · \(detail.commentsCount) comments"
        case .unknown:
            return "\(authorText) updated \(gitHubRelativeDateText(detail.updatedAt)) · \(detail.commentsCount) comments"
        }
    }

    private var trimmedBodyText: String? {
        let trimmed = detail.body?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private var trimmedCommentDraft: String? {
        let trimmed = viewModel.issueCommentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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

    private func timelineEntry(
        iconSystemName: String,
        iconTint: Color,
        authorText: String,
        headline: String,
        bodyText: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(iconTint.opacity(0.12))
                    .frame(width: 28, height: 28)
                Image(systemName: iconSystemName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(iconTint)
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 8) {
                    Text(authorText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NativeTheme.textPrimary)

                    Text(headline)
                        .font(.caption)
                        .foregroundStyle(NativeTheme.textSecondary)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(NativeTheme.elevated)

                Rectangle()
                    .fill(NativeTheme.border)
                    .frame(height: 1)

                WorkspaceGitHubRenderedContentView(content: bodyText)
                    .padding(14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NativeTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(NativeTheme.border, lineWidth: 1)
            )
            .clipShape(.rect(cornerRadius: 12))
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
