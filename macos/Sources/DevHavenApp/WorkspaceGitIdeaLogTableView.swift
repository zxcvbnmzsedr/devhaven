import SwiftUI
import DevHavenCore

struct WorkspaceGitIdeaLogTableView: View {
    @Bindable var viewModel: WorkspaceGitLogViewModel
    let onOpenCommitDiff: (WorkspaceGitCommitSummary) -> Void
    private let defaultColumns = WorkspaceGitLogColumn.defaultColumns
    @State private var hoveredCommitHash: String?

    private enum TableCellMetrics {
        static let verticalInsetCompensation: CGFloat = 4
        static let horizontalPadding: CGFloat = 4
        static let rowHeight: CGFloat = 28
        static let subjectMinWidth: CGFloat = 360
        static let subjectIdealWidth: CGFloat = 560
        static let authorMinWidth: CGFloat = 140
        static let authorIdealWidth: CGFloat = 180
        static let authorMaxWidth: CGFloat = 260
        static let dateMinWidth: CGFloat = 150
        static let dateIdealWidth: CGFloat = 170
        static let dateMaxWidth: CGFloat = 220
        static let hashMinWidth: CGFloat = 110
        static let hashIdealWidth: CGFloat = 120
        static let hashMaxWidth: CGFloat = 150
    }

    private var selectionBinding: Binding<String?> {
        Binding(
            get: { viewModel.selectedCommitHash },
            set: { viewModel.selectCommit($0) }
        )
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
                Table(tableRows, selection: selectionBinding) {
                    TableColumn(defaultColumns[0].title) { row in
                        subjectCell(row, graphWidth: graphWidth)
                    }
                    .width(min: TableCellMetrics.subjectMinWidth, ideal: TableCellMetrics.subjectIdealWidth)
                    TableColumn(defaultColumns[1].title) { row in
                        tableCell(row) {
                            Text(row.commit.authorName)
                                .font(.callout)
                                .foregroundStyle(NativeTheme.textPrimary)
                                .lineLimit(1)
                        }
                    }
                    .width(
                        min: TableCellMetrics.authorMinWidth,
                        ideal: TableCellMetrics.authorIdealWidth,
                        max: TableCellMetrics.authorMaxWidth
                    )
                    TableColumn(defaultColumns[2].title) { row in
                        tableCell(row) {
                            Text(row.formattedDateText)
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(NativeTheme.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    .width(
                        min: TableCellMetrics.dateMinWidth,
                        ideal: TableCellMetrics.dateIdealWidth,
                        max: TableCellMetrics.dateMaxWidth
                    )
                    TableColumn(defaultColumns[3].title) { row in
                        tableCell(row) {
                            Text(row.commit.shortHash)
                                .font(.callout.monospaced())
                                .foregroundStyle(NativeTheme.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    .width(
                        min: TableCellMetrics.hashMinWidth,
                        ideal: TableCellMetrics.hashIdealWidth,
                        max: TableCellMetrics.hashMaxWidth
                    )
                }
                .tableStyle(.inset)
            }
        }
        .background(NativeTheme.window)
    }

    private func subjectCell(_ row: WorkspaceGitLogTableRow, graphWidth: Double) -> some View {
        let commit = row.commit
        return tableCell(row) {
            HStack(spacing: 8) {
                WorkspaceGitCommitGraphView(
                    row: row.graphRow,
                    width: graphWidth
                )
                .frame(
                    width: graphWidth,
                    height: TableCellMetrics.rowHeight,
                    alignment: .leading
                )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(commit.subject)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(NativeTheme.textPrimary)
                            .lineLimit(1)
                        ForEach(row.decorationBadges, id: \.self) { badge in
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
        }
    }

    private func tableCell<Content: View>(
        _ row: WorkspaceGitLogTableRow,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
            .frame(height: TableCellMetrics.rowHeight, alignment: .leading)
            .padding(.horizontal, TableCellMetrics.horizontalPadding)
            .background(rowBackground(for: row))
            .padding(.vertical, -TableCellMetrics.verticalInsetCompensation)
            .contentShape(Rectangle())
            .onHover { isHovered in
                updateHoveredCommit(row.commit.hash, isHovered: isHovered)
            }
            .contextMenu {
                Button("打开差异") {
                    onOpenCommitDiff(row.commit)
                }
            }
            .help("双击打开差异")
            .accessibilityAction(named: Text("打开差异")) {
                onOpenCommitDiff(row.commit)
            }
            .onTapGesture(count: 2) {
                onOpenCommitDiff(row.commit)
            }
    }

    private func updateHoveredCommit(_ hash: String, isHovered: Bool) {
        if isHovered {
            hoveredCommitHash = hash
        } else if hoveredCommitHash == hash {
            hoveredCommitHash = nil
        }
    }

    private func rowBackground(for row: WorkspaceGitLogTableRow) -> Color {
        if viewModel.selectedCommitHash == row.commit.hash {
            return .clear
        }
        if hoveredCommitHash == row.commit.hash {
            return NativeTheme.accent.opacity(row.isHighlightedOnCurrentBranch ? 0.12 : 0.06)
        }
        if row.isHighlightedOnCurrentBranch {
            return NativeTheme.accent.opacity(0.08)
        }
        return .clear
    }
}
