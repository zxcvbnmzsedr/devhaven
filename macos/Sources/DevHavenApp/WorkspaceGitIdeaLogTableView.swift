import SwiftUI
import DevHavenCore

struct WorkspaceGitIdeaLogTableView: View {
    @Bindable var viewModel: WorkspaceGitLogViewModel
    private let defaultColumns = WorkspaceGitLogColumn.defaultColumns
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM/dd"
        return formatter
    }()

    private enum TableCellMetrics {
        static let verticalInsetCompensation: CGFloat = 4
    }

    var body: some View {
        let tableRows = viewModel.tableRows
        let graphWidth = viewModel.preferredGraphWidth

        Group {
            if viewModel.isLoading && viewModel.logSnapshot.commits.isEmpty {
                ProgressView("正在加载日志…")
                    .tint(NativeTheme.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.logSnapshot.commits.isEmpty {
                ContentUnavailableView(
                    "暂无提交",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("当前筛选条件下没有可展示的提交。")
                )
                .foregroundStyle(NativeTheme.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(tableRows) {
                    TableColumn(defaultColumns[0].title) { row in
                        subjectCell(row, graphWidth: graphWidth)
                    }
                    TableColumn(defaultColumns[1].title) { row in
                        Text(row.commit.authorName)
                            .font(.callout)
                            .foregroundStyle(NativeTheme.textPrimary)
                    }
                    TableColumn(defaultColumns[2].title) { row in
                        Text(formattedCommitTimestamp(row.commit.authorTimestamp))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(NativeTheme.textSecondary)
                    }
                    TableColumn(defaultColumns[3].title) { row in
                        Text(row.commit.shortHash)
                            .font(.callout.monospaced())
                            .foregroundStyle(NativeTheme.textSecondary)
                    }
                }
                .tableStyle(.inset)
            }
        }
        .background(NativeTheme.window)
    }

    private func subjectCell(_ row: WorkspaceGitLogTableRow, graphWidth: Double) -> some View {
        let commit = row.commit
        return Button {
            viewModel.selectCommit(commit.hash)
        } label: {
            HStack(spacing: 8) {
                WorkspaceGitCommitGraphView(
                    row: row.graphRow,
                    width: graphWidth
                )
                .frame(
                    width: graphWidth,
                    height: WorkspaceGitCommitGraphView.rowHeight,
                    alignment: .leading
                )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(commit.subject)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(NativeTheme.textPrimary)
                            .lineLimit(1)
                        ForEach(decorationBadges(for: commit), id: \.self) { badge in
                            Text(badge)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(NativeTheme.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(NativeTheme.accent.opacity(0.12))
                                .clipShape(.capsule)
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
            .frame(height: WorkspaceGitCommitGraphView.rowHeight, alignment: .leading)
            .background(rowBackground(for: commit))
            .padding(.vertical, -TableCellMetrics.verticalInsetCompensation)
        }
        .buttonStyle(.plain)
    }

    private func rowBackground(for commit: WorkspaceGitCommitSummary) -> Color {
        if viewModel.selectedCommitHash == commit.hash {
            return NativeTheme.accent.opacity(0.16)
        }
        if viewModel.isCommitHighlightedOnCurrentBranch(commit) {
            return NativeTheme.accent.opacity(0.08)
        }
        return .clear
    }

    private func decorationBadges(for commit: WorkspaceGitCommitSummary) -> [String] {
        guard let decorations = commit.decorations?
            .trimmingCharacters(in: CharacterSet(charactersIn: "() ").union(.whitespacesAndNewlines)),
              !decorations.isEmpty
        else {
            return []
        }
        return decorations
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func formattedCommitTimestamp(_ authorTimestamp: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: authorTimestamp)
        if Calendar.current.isDateInToday(date) {
            return "今天"
        }
        if Calendar.current.isDateInYesterday(date) {
            return "昨天"
        }
        return Self.dateFormatter.string(from: date)
    }
}
