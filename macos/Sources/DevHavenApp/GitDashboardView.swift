import SwiftUI
import AppKit
import DevHavenCore

struct GitDashboardView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: NativeAppViewModel

    @State private var selectedRange: GitDashboardRange = .oneYear
    @State private var updateMessage: String?
    @State private var updateError: String?

    var body: some View {
        GeometryReader { proxy in
            let summary = viewModel.gitDashboardSummary(for: selectedRange)
            let heatmapDays = viewModel.gitDashboardHeatmapDays(for: selectedRange)
            let dailyActivities = viewModel.gitDashboardDailyActivities(for: selectedRange)
            let projectActivities = viewModel.gitDashboardProjectActivities(for: selectedRange)
            let layout = buildGitDashboardLayoutPlan(width: proxy.size.width)

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        rangePicker

                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(minimum: 150), spacing: 14), count: layout.statColumnCount),
                            spacing: 14
                        ) {
                            StatCard(title: "总项目数", value: "\(summary.projectCount)")
                            StatCard(title: "Git 项目", value: "\(summary.gitProjectCount)")
                            StatCard(title: "标签数", value: "\(summary.tagCount)")
                            StatCard(title: "活跃天数", value: "\(summary.activeDays)")
                            StatCard(title: "总提交数", value: "\(summary.totalCommits)")
                            StatCard(title: "活跃率", value: "\(Int(round(summary.activityRate * 100)))%")
                        }

                        sectionCard(title: "开发热力图", subtitle: "\(selectedRange.title) · 日均 \(summary.averageCommitsPerDay.formatted(.number.precision(.fractionLength(1)))) 次提交") {
                            if heatmapDays.isEmpty {
                                emptyState("暂无提交数据")
                            } else {
                                GitHeatmapGridView(
                                    days: heatmapDays,
                                    style: .dashboard,
                                    selectedDateKey: nil,
                                    onSelectDate: nil
                                )
                            }
                        }

                        Group {
                            if layout.stackSecondarySectionsVertically {
                                VStack(alignment: .leading, spacing: 16) {
                                    recentDailySection(dailyActivities)
                                    activeProjectsSection(projectActivities)
                                }
                            } else {
                                HStack(alignment: .top, spacing: 16) {
                                    recentDailySection(dailyActivities)
                                    activeProjectsSection(projectActivities)
                                }
                            }
                        }
                    }
                    .padding(22)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 920, minHeight: 760)
        .background(NativeTheme.window)
        .background(
            DashboardWindowConfigurator(
                minSize: NSSize(width: 920, height: 760),
                initialSize: NSSize(width: 1260, height: 860)
            )
        )
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("项目仪表盘")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(NativeTheme.textPrimary)
                Text("最后更新：\(lastUpdatedLabel)")
                    .font(.subheadline)
                    .foregroundStyle(NativeTheme.textSecondary)
            }

            Spacer(minLength: 12)

            HStack(spacing: 10) {
                Button(viewModel.isRefreshingGitStatistics ? "更新中..." : "更新统计") {
                    refreshStatistics()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isRefreshingGitStatistics)

                Button("关闭") {
                    viewModel.hideDashboard()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(NativeTheme.accent)
            }
        }
        .padding(22)
        .background(NativeTheme.surface)
        .overlay(alignment: .bottomLeading) {
            if viewModel.isRefreshingGitStatistics, let progressText = viewModel.gitStatisticsProgressText {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(NativeTheme.accent)
                    Text(progressText)
                        .font(.caption)
                        .foregroundStyle(NativeTheme.textSecondary)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let updateError {
                Text(updateError)
                    .font(.caption)
                    .foregroundStyle(NativeTheme.danger)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let updateMessage {
                Text(updateMessage)
                    .font(.caption)
                    .foregroundStyle(NativeTheme.textSecondary)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var rangePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(GitDashboardRange.allCases) { range in
                    Button {
                        selectedRange = range
                    } label: {
                        Text(range.title)
                            .font(.headline)
                            .foregroundStyle(selectedRange == range ? Color.white : NativeTheme.textPrimary)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(
                                selectedRange == range
                                    ? NativeTheme.accent
                                    : NativeTheme.elevated
                            )
                            .clipShape(.capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func recentDailySection(_ dailyActivities: [GitDashboardDailyActivity]) -> some View {
        sectionCard(title: "最近活跃日期", subtitle: "按日期查看最近的提交热度") {
            if dailyActivities.isEmpty {
                emptyState("暂无活跃记录")
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(dailyActivities.prefix(8))) { item in
                        HStack(spacing: 12) {
                            Text(shortDate(item.date))
                                .font(.headline)
                                .foregroundStyle(NativeTheme.textPrimary)
                            Spacer(minLength: 8)
                            Text("\(item.commitCount) 次提交 · \(item.projectPaths.count) 个项目")
                                .font(.caption)
                                .foregroundStyle(NativeTheme.textSecondary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(NativeTheme.elevated)
                        .clipShape(.rect(cornerRadius: 14))
                    }
                }
            }
        }
    }

    private func activeProjectsSection(_ projectActivities: [GitDashboardProjectActivity]) -> some View {
        sectionCard(title: "最活跃项目", subtitle: "按选中时间范围累计提交排序") {
            if projectActivities.isEmpty {
                emptyState("暂无 Git 项目")
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(projectActivities.prefix(8))) { item in
                        Button {
                            viewModel.selectProject(item.path)
                            viewModel.hideDashboard()
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name)
                                        .font(.headline)
                                        .foregroundStyle(NativeTheme.textPrimary)
                                    Text(item.path)
                                        .font(.caption2)
                                        .foregroundStyle(NativeTheme.textSecondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                Text("\(item.commitCount) 次提交 · \(item.activeDays) 天活跃")
                                    .font(.caption)
                                    .foregroundStyle(NativeTheme.textSecondary)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(NativeTheme.elevated)
                            .clipShape(.rect(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func sectionCard<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(NativeTheme.textPrimary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(NativeTheme.textSecondary)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(NativeTheme.surface)
        .clipShape(.rect(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(NativeTheme.border, lineWidth: 1)
        )
    }

    private func emptyState(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(NativeTheme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 18)
    }

    private var lastUpdatedLabel: String {
        guard let date = viewModel.gitStatisticsLastUpdated else {
            return "未同步"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: date)
    }

    private func refreshStatistics() {
        updateError = nil
        updateMessage = nil
        Task {
            do {
                let summary = try await viewModel.refreshGitStatisticsAsync()
                updateMessage = "统计已更新：\(summary.updatedRepositories)/\(summary.requestedRepositories) 个仓库刷新成功。"
                if summary.failedRepositories > 0 {
                    updateMessage = (updateMessage ?? "") + " \(summary.failedRepositories) 个仓库刷新失败。"
                }
            } catch {
                updateError = error.localizedDescription
            }
        }
    }
}

private struct StatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(NativeTheme.textSecondary)
            Text(value)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(NativeTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .padding(18)
        .background(NativeTheme.surface)
        .clipShape(.rect(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(NativeTheme.border, lineWidth: 1)
        )
    }
}

private struct DashboardWindowConfigurator: NSViewRepresentable {
    let minSize: NSSize
    let initialSize: NSSize

    final class Coordinator {
        var configuredWindowNumber: Int?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configureWindowIfNeeded(for: view, coordinator: context.coordinator)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindowIfNeeded(for: nsView, coordinator: context.coordinator)
        }
    }

    private func configureWindowIfNeeded(for view: NSView, coordinator: Coordinator) {
        guard let window = view.window else {
            return
        }
        window.styleMask.insert(.resizable)
        window.minSize = minSize

        let windowNumber = window.windowNumber
        guard coordinator.configuredWindowNumber != windowNumber else {
            return
        }
        coordinator.configuredWindowNumber = windowNumber

        let targetFrameSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: initialSize)).size
        var nextFrame = window.frame
        nextFrame.size.width = max(nextFrame.size.width, targetFrameSize.width)
        nextFrame.size.height = max(nextFrame.size.height, targetFrameSize.height)
        window.setFrame(nextFrame, display: true, animate: false)
    }
}
