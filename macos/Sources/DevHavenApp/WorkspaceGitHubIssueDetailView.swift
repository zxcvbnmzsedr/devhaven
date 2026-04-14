import AppKit
import SwiftUI
import DevHavenCore

struct WorkspaceGitHubIssueDetailView: View {
    let detail: WorkspaceGitHubIssueDetail
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

    private var bodySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Description")
                .font(.headline)
                .foregroundStyle(NativeTheme.textPrimary)
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
        .padding(14)
        .background(NativeTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(NativeTheme.border, lineWidth: 1)
        )
        .clipShape(.rect(cornerRadius: 14))
    }

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Comments")
                .font(.headline)
                .foregroundStyle(NativeTheme.textPrimary)
            if detail.comments.isEmpty {
                Text("暂无评论")
                    .font(.callout)
                    .foregroundStyle(NativeTheme.textSecondary)
            } else {
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
