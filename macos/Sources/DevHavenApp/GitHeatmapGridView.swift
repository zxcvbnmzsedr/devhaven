import SwiftUI
import DevHavenCore

struct GitHeatmapGridView: View {
    enum Style: Equatable {
        case sidebar
        case dashboard

        var cellSize: CGFloat {
            switch self {
            case .sidebar:
                return 12
            case .dashboard:
                return 18
            }
        }

        var cellSpacing: CGFloat {
            switch self {
            case .sidebar:
                return 4
            case .dashboard:
                return 6
            }
        }

        var monthLabelHeight: CGFloat {
            switch self {
            case .sidebar:
                return 0
            case .dashboard:
                return 20
            }
        }

        var showMonthLabels: Bool {
            self == .dashboard
        }

        var showLegend: Bool {
            self == .dashboard
        }
    }

    let days: [GitHeatmapDay]
    let style: Style
    let selectedDateKey: String?
    let onSelectDate: ((String?) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: style == .sidebar ? 10 : 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: style == .sidebar ? 10 : 14) {
                    if style.showMonthLabels {
                        monthLabelsView
                    }

                    HStack(alignment: .top, spacing: style.cellSpacing) {
                        ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                            VStack(spacing: style.cellSpacing) {
                                ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                                    heatmapCell(day)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            if style.showLegend {
                HStack(spacing: 6) {
                    Text("少")
                    ForEach(0..<5, id: \.self) { level in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(NativeTheme.heatmapColor(level: level))
                            .frame(width: 14, height: 14)
                    }
                    Text("多")
                }
                .font(.caption2)
                .foregroundStyle(NativeTheme.textSecondary)
            }
        }
    }

    private var weeks: [[GitHeatmapDay?]] {
        guard let firstDay = days.first else {
            return []
        }
        let startWeekday = max(0, Calendar.current.component(.weekday, from: firstDay.date) - 1)
        let totalCells = startWeekday + days.count
        let weekCount = Int(ceil(Double(totalCells) / 7.0))
        var results = Array(repeating: Array<GitHeatmapDay?>(repeating: nil, count: 7), count: weekCount)

        for (index, day) in days.enumerated() {
            let cellIndex = startWeekday + index
            let weekIndex = cellIndex / 7
            let dayIndex = cellIndex % 7
            results[weekIndex][dayIndex] = day
        }
        return results
    }

    private var monthLabelsView: some View {
        HStack(spacing: style.cellSpacing) {
            ForEach(Array(buildMonthLabels().enumerated()), id: \.offset) { _, label in
                ZStack(alignment: .leading) {
                    Color.clear
                        .frame(width: style.cellSize, height: style.monthLabelHeight)

                    if !label.isEmpty {
                        Text(label)
                            .font(.caption2)
                            .foregroundStyle(NativeTheme.textSecondary)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
        }
        .frame(height: style.monthLabelHeight, alignment: .bottom)
    }

    @ViewBuilder
    private func heatmapCell(_ day: GitHeatmapDay?) -> some View {
        if let day {
            Button {
                onSelectDate?(day.commitCount > 0 ? day.dateKey : nil)
            } label: {
                RoundedRectangle(cornerRadius: 4)
                    .fill(NativeTheme.heatmapColor(level: day.intensity))
                    .frame(width: style.cellSize, height: style.cellSize)
                    .overlay {
                        if selectedDateKey == day.dateKey {
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(NativeTheme.accent, lineWidth: 1.5)
                        }
                    }
            }
            .buttonStyle(.plain)
            .disabled(onSelectDate == nil)
            .help(tooltipText(for: day))
            .accessibilityLabel(tooltipText(for: day))
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.clear)
                .frame(width: style.cellSize, height: style.cellSize)
                .accessibilityHidden(true)
        }
    }

    private func buildMonthLabels() -> [String] {
        var lastMonth: Int?
        return weeks.map { week in
            guard let firstDay = week.compactMap({ $0 }).first else {
                return ""
            }
            let month = Calendar.current.component(.month, from: firstDay.date)
            defer { lastMonth = month }
            guard lastMonth != month else {
                return ""
            }
            return "\(month)月"
        }
    }

    private func tooltipText(for day: GitHeatmapDay) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy/MM/dd"
        let projectLabel = day.projectPaths.isEmpty ? "" : " · \(day.projectPaths.count) 个项目"
        let commitLabel = day.commitCount == 0 ? "无提交" : "\(day.commitCount) 次提交"
        return "\(formatter.string(from: day.date))：\(commitLabel)\(projectLabel)"
    }
}
