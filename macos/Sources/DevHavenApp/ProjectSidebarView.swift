import SwiftUI
import DevHavenCore

struct ProjectSidebarView: View {
    @Bindable var viewModel: NativeAppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sidebarSection(title: "目录", trailingSystemImage: "plus.circle") {
                    VStack(spacing: 6) {
                        ForEach(viewModel.directoryRows) { row in
                            sidebarRow(
                                title: row.title,
                                count: row.count,
                                selected: row.path == viewModel.selectedDirectory || (row.path == nil && viewModel.selectedDirectory == nil)
                            ) {
                                viewModel.selectDirectory(row.path)
                            }
                        }
                    }
                }

                sidebarSection(title: "开发热力图", trailingSystemImage: nil) {
                    if viewModel.heatmapCells.isEmpty {
                        Text("暂无 Git 活跃度数据")
                            .font(.caption)
                            .foregroundStyle(NativeTheme.textSecondary)
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(12), spacing: 4), count: 10), spacing: 4) {
                            ForEach(viewModel.heatmapCells) { cell in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(NativeTheme.heatmapColor(level: cell.intensity))
                                    .frame(width: 12, height: 12)
                                    .help("\(cell.dateKey)：\(cell.count) 次提交")
                            }
                        }
                    }
                }

                sidebarSection(title: "CLI 会话", trailingSystemImage: nil) {
                    if viewModel.cliSessionItems.isEmpty {
                        Text("终端工作区尚未迁入原生版")
                            .font(.caption)
                            .foregroundStyle(NativeTheme.textSecondary)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(viewModel.cliSessionItems) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Circle()
                                            .fill(NativeTheme.success)
                                            .frame(width: 7, height: 7)
                                        Text(item.title)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(NativeTheme.textPrimary)
                                        Spacer()
                                        Text(item.statusText)
                                            .font(.caption2)
                                            .foregroundStyle(NativeTheme.textSecondary)
                                    }
                                    Text(item.subtitle)
                                        .font(.caption2)
                                        .foregroundStyle(NativeTheme.textSecondary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(NativeTheme.elevated)
                                .clipShape(.rect(cornerRadius: 10))
                            }
                        }
                    }
                }

                sidebarSection(title: "标签", trailingSystemImage: "plus.circle") {
                    VStack(spacing: 6) {
                        ForEach(viewModel.tagRows) { row in
                            sidebarRow(
                                title: row.title,
                                count: row.count,
                                selected: row.name == viewModel.selectedTag || (row.name == nil && viewModel.selectedTag == nil),
                                accentHex: row.colorHex
                            ) {
                                viewModel.selectTag(row.name)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
        }
    }

    private func sidebarSection<Content: View>(title: String, trailingSystemImage: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(NativeTheme.textPrimary)
                Spacer()
                if let trailingSystemImage {
                    Image(systemName: trailingSystemImage)
                        .font(.caption)
                        .foregroundStyle(NativeTheme.textSecondary)
                }
            }
            content()
        }
    }

    private func sidebarRow(title: String, count: Int, selected: Bool, accentHex: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let accentHex {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: accentHex) ?? NativeTheme.accent)
                        .frame(width: 6, height: 18)
                }
                Text(title)
                    .font(.callout)
                    .foregroundStyle(NativeTheme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(selected ? Color.white : NativeTheme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(selected ? NativeTheme.accent.opacity(0.85) : Color.white.opacity(0.05))
                    .clipShape(.rect(cornerRadius: 6))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? NativeTheme.accent.opacity(0.18) : Color.clear)
            .clipShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

private extension Color {
    init?(hex: String) {
        var normalized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("#") {
            normalized.removeFirst()
        }
        guard normalized.count == 6, let value = Int(normalized, radix: 16) else {
            return nil
        }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
