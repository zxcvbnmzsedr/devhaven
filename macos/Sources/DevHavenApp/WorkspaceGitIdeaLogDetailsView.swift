import SwiftUI
import DevHavenCore

struct WorkspaceGitIdeaLogDetailsView: View {
    @Bindable var viewModel: WorkspaceGitLogViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            detailHeader
            Divider()
                .overlay(NativeTheme.border)

            ScrollView {
                if let detail = viewModel.selectedCommitDetail {
                    VStack(alignment: .leading, spacing: 16) {
                        detailSection("提交信息") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(detail.subject)
                                    .font(.headline)
                                    .foregroundStyle(NativeTheme.textPrimary)
                                    .textSelection(.enabled)
                                if let body = detail.body, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text(body)
                                        .font(.callout)
                                        .foregroundStyle(NativeTheme.textPrimary)
                                        .textSelection(.enabled)
                                }
                            }
                        }

                        detailSection("元数据") {
                            VStack(alignment: .leading, spacing: 10) {
                                metadataRow("提交", detail.shortHash)
                                metadataRow("作者", "\(detail.authorName) <\(detail.authorEmail)>")
                                metadataRow("时间", formattedTimestamp(detail.authorTimestamp))
                            }
                        }

                        referencesSection(detail)
                        parentsSection(detail)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ContentUnavailableView(
                        "提交详情",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("选择提交后，这里会显示 message、作者、时间与 refs。")
                    )
                    .foregroundStyle(NativeTheme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 40)
                }
            }
        }
        .background(NativeTheme.window)
    }

    private var detailHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("提交详情")
                .font(.caption.weight(.semibold))
                .foregroundStyle(NativeTheme.textPrimary)
            if let detail = viewModel.selectedCommitDetail {
                Text(detail.shortHash)
                    .font(.caption.monospaced())
                    .foregroundStyle(NativeTheme.textSecondary)
            } else {
                Text("未选择")
                    .font(.caption)
                    .foregroundStyle(NativeTheme.textSecondary)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(NativeTheme.surface)
    }

    private func detailSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(NativeTheme.textSecondary)
            content()
        }
    }

    private func referencesSection(_ detail: WorkspaceGitCommitDetail) -> some View {
        detailSection("引用") {
            let branches = branchReferenceItems(for: detail)
            let tags = tagReferenceItems(for: detail)
            if branches.isEmpty && tags.isEmpty {
                Text("暂无")
                    .font(.caption)
                    .foregroundStyle(NativeTheme.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if !branches.isEmpty {
                        ReferenceBadgeList(items: branches, style: .branch, badgeBuilder: referenceBadge)
                    }
                    if !tags.isEmpty {
                        ReferenceBadgeList(items: tags, style: .tag, badgeBuilder: referenceBadge)
                    }
                }
            }
        }
    }

    private func parentsSection(_ detail: WorkspaceGitCommitDetail) -> some View {
        detailSection("父提交") {
            if detail.parentHashes.isEmpty {
                Text("暂无")
                    .font(.caption)
                    .foregroundStyle(NativeTheme.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(detail.parentHashes, id: \.self) { parent in
                        Text(parent)
                            .font(.caption.monospaced())
                            .foregroundStyle(NativeTheme.textPrimary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private func metadataRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(NativeTheme.textSecondary)
            Text(value)
                .font(.callout.monospaced())
                .foregroundStyle(NativeTheme.textPrimary)
                .textSelection(.enabled)
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter
    }()

    private func formattedTimestamp(_ timestamp: TimeInterval) -> String {
        Self.timestampFormatter.string(from: Date(timeIntervalSince1970: timestamp))
    }

    private func branchReferenceItems(for detail: WorkspaceGitCommitDetail) -> [String] {
        referenceItems(for: detail).filter { !$0.hasPrefix("tag: ") }
    }

    private func tagReferenceItems(for detail: WorkspaceGitCommitDetail) -> [String] {
        referenceItems(for: detail)
            .filter { $0.hasPrefix("tag: ") }
            .map { String($0.dropFirst("tag: ".count)) }
    }

    private func referenceItems(for detail: WorkspaceGitCommitDetail) -> [String] {
        guard let decorations = detail.decorations else { return [] }
        return decorations
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func referenceBadge(_ item: String, style: ReferenceBadgeStyle) -> some View {
        Text(item)
            .font(.caption.monospaced())
            .foregroundStyle(style.foregroundColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(style.backgroundColor)
            .clipShape(.capsule)
    }
}

private enum ReferenceBadgeStyle {
    case branch
    case tag

    var foregroundColor: Color {
        switch self {
        case .branch:
            return NativeTheme.accent
        case .tag:
            return NativeTheme.textPrimary
        }
    }

    var backgroundColor: Color {
        switch self {
        case .branch:
            return NativeTheme.accent.opacity(0.14)
        case .tag:
            return NativeTheme.elevated
        }
    }
}

private struct ReferenceBadgeList<Badge: View>: View {
    let items: [String]
    let style: ReferenceBadgeStyle
    let badgeBuilder: (String, ReferenceBadgeStyle) -> Badge

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(chunked(items, size: 2), id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { item in
                        badgeBuilder(item, style)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func chunked(_ items: [String], size: Int) -> [[String]] {
        stride(from: 0, to: items.count, by: size).map { index in
            Array(items[index..<min(index + size, items.count)])
        }
    }
}
