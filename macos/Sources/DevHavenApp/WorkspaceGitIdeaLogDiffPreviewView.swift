import SwiftUI
import DevHavenCore

struct WorkspaceGitIdeaLogDiffPreviewView: View {
    @Bindable var viewModel: WorkspaceGitLogViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Diff 预览")
                    .font(.headline)
                    .foregroundStyle(NativeTheme.textPrimary)
                if let selectedFilePath = viewModel.selectedFilePath {
                    Text(selectedFilePath)
                        .font(.caption.monospaced())
                        .foregroundStyle(NativeTheme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
            }

            if let selectedFileDiffNotice = viewModel.selectedFileDiffNotice {
                Text(selectedFileDiffNotice)
                    .font(.caption)
                    .foregroundStyle(NativeTheme.warning)
            }

            if viewModel.isLoadingSelectedFileDiff {
                ProgressView("正在加载 Diff…")
                    .tint(NativeTheme.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.selectedFilePath == nil {
                ContentUnavailableView(
                    "选择一个文件",
                    systemImage: "doc.plaintext",
                    description: Text("从下方变更列表选择文件后，这里会展示文件级 Diff。")
                )
                .foregroundStyle(NativeTheme.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.selectedFileDiff.isEmpty {
                Text("当前文件没有可展示的 Diff。")
                    .font(.caption)
                    .foregroundStyle(NativeTheme.textSecondary)
            } else {
                ScrollView {
                    Text(viewModel.selectedFileDiff)
                        .font(.callout.monospaced())
                        .foregroundStyle(NativeTheme.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .background(NativeTheme.elevated)
                .clipShape(.rect(cornerRadius: 10))
            }
        }
        .padding(16)
        .background(NativeTheme.window)
    }
}
