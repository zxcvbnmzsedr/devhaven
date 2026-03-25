import SwiftUI
import DevHavenCore

struct WorkspaceGitIdeaLogDetailsView: View {
    @Bindable var viewModel: WorkspaceGitLogViewModel

    var body: some View {
        ScrollView {
            if let detail = viewModel.selectedCommitDetail {
                VStack(alignment: .leading, spacing: 16) {
                    Text(detail.subject)
                        .font(.headline)
                        .foregroundStyle(NativeTheme.textPrimary)
                        .textSelection(.enabled)

                    metadataRow("提交", detail.shortHash)
                    metadataRow("作者", "\(detail.authorName) <\(detail.authorEmail)>")
                    metadataRow("时间", formattedTimestamp(detail.authorTimestamp))
                    if let decorations = detail.decorations, !decorations.isEmpty {
                        metadataRow("引用", decorations)
                    }
                    if !detail.parentHashes.isEmpty {
                        metadataRow("父提交", detail.parentHashes.joined(separator: ", "))
                    }
                    if let body = detail.body, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(body)
                            .font(.callout)
                            .foregroundStyle(NativeTheme.textPrimary)
                            .textSelection(.enabled)
                    }
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
        .background(NativeTheme.window)
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

    private func formattedTimestamp(_ timestamp: TimeInterval) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: timestamp))
    }
}
