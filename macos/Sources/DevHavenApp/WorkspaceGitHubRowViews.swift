import Foundation
import SwiftUI
import DevHavenCore

func gitHubRelativeDateText(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter.localizedString(for: date, relativeTo: Date())
}

func gitHubAbsoluteDateText(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

func gitHubLabelColor(_ hex: String) -> Color {
    let sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
    guard sanitized.count == 6, let value = Int(sanitized, radix: 16) else {
        return NativeTheme.accent
    }
    let red = Double((value >> 16) & 0xFF) / 255
    let green = Double((value >> 8) & 0xFF) / 255
    let blue = Double(value & 0xFF) / 255
    return Color(red: red, green: green, blue: blue)
}

func gitHubPullStateTitle(_ state: WorkspaceGitHubPullState, isDraft: Bool) -> String {
    if isDraft {
        return "Draft"
    }
    switch state {
    case .open:
        return "Open"
    case .closed:
        return "Closed"
    case .merged:
        return "Merged"
    case let .unknown(value):
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown" : trimmed
    }
}

func gitHubIssueStateReasonTitle(_ reason: WorkspaceGitHubIssueStateReason) -> String {
    switch reason {
    case .completed:
        return "Completed"
    case .notPlanned:
        return "Not planned"
    case .reopened:
        return "Reopened"
    case .none:
        return "None"
    case let .unknown(value):
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown" : trimmed
    }
}

func gitHubIssueStateTitle(
    _ state: WorkspaceGitHubIssueState,
    reason: WorkspaceGitHubIssueStateReason = .none
) -> String {
    switch state {
    case .open:
        return "Open"
    case .closed:
        return reason == .none ? "Closed" : "Closed · \(gitHubIssueStateReasonTitle(reason))"
    case let .unknown(value):
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown" : trimmed
    }
}

func gitHubReviewDecisionTitle(_ decision: WorkspaceGitHubReviewDecision) -> String {
    switch decision {
    case .none:
        return "None"
    case .approved:
        return "Approved"
    case .changesRequested:
        return "Changes requested"
    case .reviewRequired:
        return "Review required"
    case let .unknown(value):
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown" : trimmed
    }
}

func gitHubMergeStateTitle(_ status: WorkspaceGitHubMergeStateStatus) -> String {
    switch status {
    case .clean:
        return "Clean"
    case .blocked:
        return "Blocked"
    case .behind:
        return "Behind"
    case .dirty:
        return "Dirty"
    case .draft:
        return "Draft"
    case .hasHooks:
        return "Has hooks"
    case .unstable:
        return "Unstable"
    case let .unknown(value):
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown" : trimmed
    }
}

func gitHubReviewSubmissionTitle(_ event: WorkspaceGitHubReviewSubmissionEvent) -> String {
    switch event {
    case .comment:
        return "评论"
    case .approve:
        return "通过"
    case .requestChanges:
        return "请求修改"
    }
}

func gitHubMutationStatusText(_ kind: WorkspaceGitHubMutationKind) -> String {
    switch kind {
    case .addIssueComment:
        return "正在提交 Issue 评论…"
    case .closeIssue:
        return "正在关闭 Issue…"
    case .reopenIssue:
        return "正在重新打开 Issue…"
    case .createIssueBranch:
        return "正在创建并切换 Issue 分支…"
    case .createIssueWorktree:
        return "已开始创建 Issue worktree…"
    case .addPullComment:
        return "正在提交 PR 评论…"
    case .closePull:
        return "正在关闭 Pull Request…"
    case .reopenPull:
        return "正在重新打开 Pull Request…"
    case let .mergePull(method):
        return "正在执行 \(method.title) …"
    case .checkoutPullBranch:
        return "正在 checkout PR 分支…"
    case let .submitReview(event):
        return "正在提交 Review\(gitHubReviewSubmissionTitle(event))…"
    }
}

func gitHubMutationSuccessText(_ kind: WorkspaceGitHubMutationKind) -> String {
    switch kind {
    case .addIssueComment:
        return "Issue 评论已提交"
    case .closeIssue:
        return "Issue 已关闭"
    case .reopenIssue:
        return "Issue 已重新打开"
    case .createIssueBranch:
        return "Issue 分支已创建并切换"
    case .createIssueWorktree:
        return "已开始创建并打开 Issue worktree"
    case .addPullComment:
        return "PR 评论已提交"
    case .closePull:
        return "Pull Request 已关闭"
    case .reopenPull:
        return "Pull Request 已重新打开"
    case let .mergePull(method):
        return "\(method.title) 已提交"
    case .checkoutPullBranch:
        return "PR 分支已 checkout"
    case let .submitReview(event):
        return "Review\(gitHubReviewSubmissionTitle(event))已提交"
    }
}

func gitHubPullStateColor(_ state: WorkspaceGitHubPullState, isDraft: Bool) -> Color {
    if isDraft {
        return NativeTheme.textSecondary
    }
    switch state {
    case .open:
        return .green
    case .closed:
        return .red
    case .merged:
        return .purple
    case .unknown:
        return NativeTheme.textSecondary
    }
}

func gitHubIssueStateColor(_ state: WorkspaceGitHubIssueState) -> Color {
    switch state {
    case .open:
        return .green
    case .closed:
        return .purple
    case .unknown:
        return NativeTheme.textSecondary
    }
}

private struct WorkspaceGitHubLabelStripView: View {
    let labels: [WorkspaceGitHubLabel]
    var limit: Int = 3

    var body: some View {
        if !labels.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(labels.prefix(limit))) { label in
                        Text(label.name)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(gitHubLabelColor(label.color ?? "").opacity(0.18))
                            .foregroundStyle(NativeTheme.textPrimary)
                            .clipShape(.capsule)
                    }
                }
            }
        }
    }
}

struct WorkspaceGitHubListLoadingOverlay: View {
    let title: String

    var body: some View {
        VStack {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NativeTheme.textPrimary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial)
            .clipShape(.capsule)
            .overlay(
                Capsule()
                    .stroke(NativeTheme.border, lineWidth: 1)
            )

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(NativeTheme.window.opacity(0.12))
        .allowsHitTesting(false)
    }
}

struct WorkspaceGitHubPullRowView: View {
    let pull: WorkspaceGitHubPullSummary
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(gitHubPullStateColor(pull.state, isDraft: pull.isDraft))
                        .frame(width: 9, height: 9)
                        .padding(.top, 5)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(pull.title)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(NativeTheme.textPrimary)
                            .lineLimit(2)

                        Text("#\(pull.number) · \(pull.headRefName) -> \(pull.baseRefName)")
                            .font(.caption)
                            .foregroundStyle(NativeTheme.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    if let author = pull.author {
                        Text(author.login ?? author.displayName)
                            .font(.caption)
                            .foregroundStyle(NativeTheme.textSecondary)
                    }
                    Text(gitHubPullStateTitle(pull.state, isDraft: pull.isDraft))
                        .font(.caption)
                        .foregroundStyle(NativeTheme.textSecondary)
                    Text(gitHubRelativeDateText(pull.updatedAt))
                        .font(.caption)
                        .foregroundStyle(NativeTheme.textSecondary)
                    Spacer(minLength: 0)
                    if pull.commentsCount > 0 {
                        Text("\(pull.commentsCount) 评论")
                            .font(.caption)
                            .foregroundStyle(NativeTheme.textSecondary)
                    }
                }

                WorkspaceGitHubLabelStripView(labels: pull.labels)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? NativeTheme.accent.opacity(0.14) : NativeTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? NativeTheme.accent.opacity(0.75) : NativeTheme.border, lineWidth: 1)
            )
            .clipShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

struct WorkspaceGitHubIssueRowView: View {
    let issue: WorkspaceGitHubIssueSummary
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(gitHubIssueStateColor(issue.state))
                        .frame(width: 9, height: 9)
                        .padding(.top, 5)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(issue.title)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(NativeTheme.textPrimary)
                            .lineLimit(2)

                        Text("#\(issue.number)")
                            .font(.caption)
                            .foregroundStyle(NativeTheme.textSecondary)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    if let author = issue.author {
                        Text(author.login ?? author.displayName)
                            .font(.caption)
                            .foregroundStyle(NativeTheme.textSecondary)
                    }
                    Text(gitHubIssueStateTitle(issue.state, reason: issue.stateReason))
                        .font(.caption)
                        .foregroundStyle(NativeTheme.textSecondary)
                    Text(gitHubRelativeDateText(issue.updatedAt))
                        .font(.caption)
                        .foregroundStyle(NativeTheme.textSecondary)
                    Spacer(minLength: 0)
                    if issue.commentsCount > 0 {
                        Text("\(issue.commentsCount) 评论")
                            .font(.caption)
                            .foregroundStyle(NativeTheme.textSecondary)
                    }
                }

                WorkspaceGitHubLabelStripView(labels: issue.labels)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? NativeTheme.accent.opacity(0.14) : NativeTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? NativeTheme.accent.opacity(0.75) : NativeTheme.border, lineWidth: 1)
            )
            .clipShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

struct WorkspaceGitHubReviewRowView: View {
    let review: WorkspaceGitHubReviewRequestSummary
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(gitHubPullStateColor(review.state, isDraft: review.isDraft))
                        .frame(width: 9, height: 9)
                        .padding(.top, 5)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(review.title)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(NativeTheme.textPrimary)
                            .lineLimit(2)

                        Text("#\(review.number)")
                            .font(.caption)
                            .foregroundStyle(NativeTheme.textSecondary)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    if let author = review.author {
                        Text(author.login ?? author.displayName)
                            .font(.caption)
                            .foregroundStyle(NativeTheme.textSecondary)
                    }
                    Text(gitHubPullStateTitle(review.state, isDraft: review.isDraft))
                        .font(.caption)
                        .foregroundStyle(NativeTheme.textSecondary)
                    Text(gitHubRelativeDateText(review.updatedAt))
                        .font(.caption)
                        .foregroundStyle(NativeTheme.textSecondary)
                    Spacer(minLength: 0)
                    if review.commentsCount > 0 {
                        Text("\(review.commentsCount) 评论")
                            .font(.caption)
                            .foregroundStyle(NativeTheme.textSecondary)
                    }
                }

                WorkspaceGitHubLabelStripView(labels: review.labels)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? NativeTheme.accent.opacity(0.14) : NativeTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? NativeTheme.accent.opacity(0.75) : NativeTheme.border, lineWidth: 1)
            )
            .clipShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}
