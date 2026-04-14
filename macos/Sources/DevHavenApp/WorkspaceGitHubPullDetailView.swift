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
                        if actionMode == .review {
                            reviewActionsSection
                        } else {
                            pullCommentSection
                        }
                        pullActionsSection
                        metrics
                        bodySection
                        commentsSection
                    }
                    .padding(16)
                }
                .background(NativeTheme.window)
            },
            trailing: {
                WorkspaceGitHubDetailSidebarView {
                    WorkspaceGitHubDetailSidebarSection(title: "Labels") {
                        WorkspaceGitHubLabelListView(labels: detail.labels)
                    }

                    WorkspaceGitHubDetailSidebarSection(title: "Assignees") {
                        WorkspaceGitHubActorListView(actors: detail.assignees)
                    }

                    WorkspaceGitHubDetailSidebarSection(title: "Details") {
                        VStack(alignment: .leading, spacing: 8) {
                            WorkspaceGitHubMetadataRow(title: "Created", value: gitHubAbsoluteDateText(detail.createdAt))
                            WorkspaceGitHubMetadataRow(title: "Updated", value: gitHubAbsoluteDateText(detail.updatedAt))
                            WorkspaceGitHubMetadataRow(title: "Base", value: detail.baseRefName)
                            WorkspaceGitHubMetadataRow(title: "Head", value: detail.headRefName)
                            WorkspaceGitHubMetadataRow(title: "Review", value: gitHubReviewDecisionTitle(detail.reviewDecision))
                            WorkspaceGitHubMetadataRow(title: "Merge", value: gitHubMergeStateTitle(detail.mergeStateStatus))
                            if let mergedAt = detail.mergedAt {
                                WorkspaceGitHubMetadataRow(title: "Merged", value: gitHubAbsoluteDateText(mergedAt))
                            }
                            if let milestone = detail.milestone {
                                WorkspaceGitHubMetadataRow(title: "Milestone", value: milestone.title)
                            }
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
                    .fill(gitHubPullStateColor(detail.state, isDraft: detail.isDraft))
                    .frame(width: 12, height: 12)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 6) {
                    Text(detail.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(NativeTheme.textPrimary)
                    Text("#\(detail.number) · \(detail.headRefName) -> \(detail.baseRefName)")
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

    private var pullActionsSection: some View {
        sectionCard(title: "Pull Request Actions") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Button("Checkout 分支") {
                        viewModel.checkoutSelectedPullBranch()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isMutating)

                    if canMergePull {
                        Button("Merge") {
                            viewModel.mergeSelectedPull()
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.isMutating)
                    }
                }

                HStack(spacing: 8) {
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
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var pullCommentSection: some View {
        sectionCard(title: "新增评论") {
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $viewModel.pullCommentDraft)
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
                        viewModel.addCommentToSelectedPull()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isMutating || viewModel.pullCommentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var reviewActionsSection: some View {
        sectionCard(title: "Review Actions") {
            VStack(alignment: .leading, spacing: 12) {
                TextEditor(text: $viewModel.reviewCommentDraft)
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
                }
            }
        }
    }

    private var metrics: some View {
        HStack(spacing: 10) {
            metricCard("Files", value: "\(detail.changedFiles)")
            metricCard("Commits", value: "\(detail.commitCount)")
            metricCard("Comments", value: "\(detail.commentsCount)")
            metricCard("State", value: gitHubPullStateTitle(detail.state, isDraft: detail.isDraft))
        }
    }

    private func metricCard(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(NativeTheme.textSecondary)
            Text(value)
                .font(.headline.weight(.semibold))
                .foregroundStyle(NativeTheme.textPrimary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NativeTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(NativeTheme.border, lineWidth: 1)
        )
        .clipShape(.rect(cornerRadius: 12))
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

    private var canMergePull: Bool {
        detail.state == .open && !detail.isDraft
    }

    private var canSubmitReview: Bool {
        detail.state == .open && !detail.isDraft
    }

    private var canSubmitReviewComment: Bool {
        canSubmitReview && !viewModel.reviewCommentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
