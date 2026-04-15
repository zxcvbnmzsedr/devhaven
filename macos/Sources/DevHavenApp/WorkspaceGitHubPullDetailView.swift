import AppKit
import SwiftUI
import DevHavenCore

enum WorkspaceGitHubPullDetailActionMode: Equatable {
    case pull
    case review
}

struct WorkspaceGitHubPullDetailView: View {
    @Bindable var viewModel: WorkspaceGitHubViewModel
    let detail: WorkspaceGitHubPullDetail
    let actionMode: WorkspaceGitHubPullDetailActionMode
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
                        composerSection
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
                            WorkspaceGitHubMetadataRow(title: "Base", value: detail.baseRefName)
                            WorkspaceGitHubMetadataRow(title: "Head", value: detail.headRefName)
                            WorkspaceGitHubMetadataRow(title: "Review", value: gitHubReviewDecisionTitle(detail.reviewDecision))
                            WorkspaceGitHubMetadataRow(title: "Merge", value: gitHubMergeStateTitle(detail.mergeStateStatus))
                            WorkspaceGitHubMetadataRow(title: "Commits", value: "\(detail.commitCount)")
                            WorkspaceGitHubMetadataRow(title: "Files", value: "\(detail.changedFiles)")
                            WorkspaceGitHubMetadataRow(title: "Comments", value: "\(detail.commentsCount)")
                            if let mergedAt = detail.mergedAt {
                                WorkspaceGitHubMetadataRow(title: "Merged", value: gitHubAbsoluteDateText(mergedAt))
                            }
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
                        pullStateBadge

                        Text(pullActivitySummary)
                            .font(.callout)
                            .foregroundStyle(NativeTheme.textSecondary)
                            .lineLimit(2)
                    }

                    Text(branchSummary)
                        .font(.caption)
                        .foregroundStyle(NativeTheme.textSecondary)
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
                iconSystemName: gitHubPullStateSymbolName(detail.state, isDraft: detail.isDraft),
                iconTint: gitHubPullStateColor(detail.state, isDraft: detail.isDraft),
                authorText: gitHubActorSummaryText(detail.author) ?? "未知用户",
                headline: "opened this pull request \(gitHubRelativeDateText(detail.createdAt))",
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

    @ViewBuilder
    private var composerSection: some View {
        switch actionMode {
        case .pull:
            sectionCard(title: "Add a comment") {
                VStack(alignment: .leading, spacing: 10) {
                    TextEditor(text: $viewModel.pullCommentDraft)
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
                            viewModel.addCommentToSelectedPull()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isMutating || trimmedPullCommentDraft == nil)
                    }
                }
            }
        case .review:
            sectionCard(title: "Review changes") {
                VStack(alignment: .leading, spacing: 12) {
                    TextEditor(text: $viewModel.reviewCommentDraft)
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
                        Button("评论") {
                            viewModel.submitReviewForSelectedPull(event: .comment)
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.isMutating || !canSubmitReviewComment)

                        Button("通过") {
                            viewModel.submitReviewForSelectedPull(event: .approve)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isMutating || !canSubmitReview)

                        Button("请求修改") {
                            viewModel.submitReviewForSelectedPull(event: .requestChanges)
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.isMutating || !canSubmitReviewComment)

                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private var statusSection: some View {
        WorkspaceGitHubDetailSidebarSection(title: "Status") {
            VStack(alignment: .leading, spacing: 12) {
                pullStateBadge

                if detail.reviewDecision != .none {
                    inlineBadge(
                        title: gitHubReviewDecisionTitle(detail.reviewDecision),
                        tint: NativeTheme.accent
                    )
                }

                if actionMode == .pull, canMergePull {
                    Button("Merge") {
                        viewModel.mergeSelectedPull()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isMutating)
                }

                switch detail.state {
                case .open:
                    Button("关闭 PR", role: .destructive) {
                        viewModel.closeSelectedPull()
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isMutating)
                case .closed:
                    Button("重新打开 PR") {
                        viewModel.reopenSelectedPull()
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isMutating)
                case .merged, .unknown:
                    EmptyView()
                }
            }
        }
    }

    private var developmentSection: some View {
        WorkspaceGitHubDetailSidebarSection(title: "Development") {
            VStack(alignment: .leading, spacing: 10) {
                Text("源分支")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NativeTheme.textSecondary)
                Text(detail.headRefName)
                    .font(.callout.monospaced())
                    .foregroundStyle(NativeTheme.textPrimary)
                    .textSelection(.enabled)

                Text("目标分支")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NativeTheme.textSecondary)
                Text(detail.baseRefName)
                    .font(.callout.monospaced())
                    .foregroundStyle(NativeTheme.textPrimary)
                    .textSelection(.enabled)

                Button("Checkout 分支") {
                    viewModel.checkoutSelectedPullBranch()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isMutating)
            }
        }
    }

    private var pullStateBadge: some View {
        let tint = gitHubPullStateColor(detail.state, isDraft: detail.isDraft)
        return HStack(spacing: 6) {
            Image(systemName: gitHubPullStateSymbolName(detail.state, isDraft: detail.isDraft))
                .font(.system(size: 12, weight: .semibold))
            Text(gitHubPullStateTitle(detail.state, isDraft: detail.isDraft))
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

    private var branchSummary: String {
        "\(detail.headRefName) -> \(detail.baseRefName)"
    }

    private var pullActivitySummary: String {
        let authorText = gitHubActorSummaryText(detail.author) ?? "未知用户"
        switch detail.state {
        case .open:
            if detail.isDraft {
                return "\(authorText) opened a draft pull request \(gitHubRelativeDateText(detail.createdAt)) · \(detail.commentsCount) comments"
            }
            return "\(authorText) opened this pull request \(gitHubRelativeDateText(detail.createdAt)) · \(detail.commentsCount) comments"
        case .closed:
            return "\(authorText) closed this pull request · updated \(gitHubRelativeDateText(detail.updatedAt))"
        case .merged:
            if let mergedAt = detail.mergedAt {
                let mergedByText = gitHubActorSummaryText(detail.mergedBy) ?? authorText
                return "\(mergedByText) merged \(gitHubRelativeDateText(mergedAt)) · \(detail.commentsCount) comments"
            }
            return "\(authorText) merged this pull request · \(detail.commentsCount) comments"
        case .unknown:
            return "\(authorText) updated \(gitHubRelativeDateText(detail.updatedAt)) · \(detail.commentsCount) comments"
        }
    }

    private var canMergePull: Bool {
        detail.state == .open && !detail.isDraft
    }

    private var canSubmitReview: Bool {
        detail.state == .open && !detail.isDraft
    }

    private var canSubmitReviewComment: Bool {
        canSubmitReview && trimmedReviewCommentDraft != nil
    }

    private var trimmedBodyText: String? {
        let trimmed = detail.body?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private var trimmedPullCommentDraft: String? {
        let trimmed = viewModel.pullCommentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var trimmedReviewCommentDraft: String? {
        let trimmed = viewModel.reviewCommentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var actionBanner: (message: String, tint: Color)? {
        if let mutationErrorMessage = viewModel.mutationErrorMessage,
           !mutationErrorMessage.isEmpty {
            return (mutationErrorMessage, NativeTheme.warning)
        }
        if let activeMutation = viewModel.activeMutation,
           viewModel.isMutating,
           isPullMutation(activeMutation) {
            return (gitHubMutationStatusText(activeMutation), NativeTheme.accent)
        }
        if let lastSuccessfulMutation = viewModel.lastSuccessfulMutation,
           isPullMutation(lastSuccessfulMutation) {
            return (gitHubMutationSuccessText(lastSuccessfulMutation), .green)
        }
        return nil
    }

    private func isPullMutation(_ kind: WorkspaceGitHubMutationKind) -> Bool {
        switch kind {
        case .addPullComment, .closePull, .reopenPull, .mergePull, .checkoutPullBranch, .submitReview:
            return true
        default:
            return false
        }
    }

    private func inlineBadge(title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12))
            .overlay(
                Capsule()
                    .stroke(tint.opacity(0.28), lineWidth: 1)
            )
            .clipShape(.capsule)
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
