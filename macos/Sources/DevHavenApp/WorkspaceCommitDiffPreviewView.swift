import SwiftUI
import DevHavenCore

struct WorkspaceCommitDiffPreviewView: View {
    @Bindable var viewModel: WorkspaceCommitViewModel

    var body: some View {
        VStack(spacing: 0) {
            header

            Group {
                if viewModel.diffPreview.isLoading, let path = viewModel.diffPreview.path {
                    ContentUnavailableView(
                        "正在加载 Diff",
                        systemImage: "hourglass",
                        description: Text("文件：\(path)")
                    )
                    .foregroundStyle(NativeTheme.textSecondary)
                } else if let errorMessage = viewModel.diffPreview.errorMessage {
                    ContentUnavailableView(
                        "Diff 加载失败",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                    .foregroundStyle(NativeTheme.warning)
                } else if let path = viewModel.diffPreview.path {
                    if viewModel.diffPreview.content.isEmpty {
                        ContentUnavailableView(
                            "Diff 暂无内容",
                            systemImage: "doc.text",
                            description: Text("文件：\(path)")
                        )
                        .foregroundStyle(NativeTheme.textSecondary)
                    } else {
                        ScrollView {
                            Text(viewModel.diffPreview.content)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(NativeTheme.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .padding(12)
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "选择变更以查看 Diff",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("选择左侧 changes browser 的文件后，这里会展示对应 patch。")
                    )
                    .foregroundStyle(NativeTheme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(NativeTheme.window)
    }

    private var header: some View {
        HStack {
            Text("Diff Preview")
                .font(.callout.weight(.semibold))
                .foregroundStyle(NativeTheme.textPrimary)
            Spacer(minLength: 8)
            if viewModel.diffPreview.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(NativeTheme.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(NativeTheme.border)
                .frame(height: 1)
        }
    }
}
