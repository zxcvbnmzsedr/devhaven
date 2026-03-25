import SwiftUI
import DevHavenCore

struct WorkspaceCommitDiffPreviewView: View {
    @Bindable var viewModel: WorkspaceCommitViewModel

    var body: some View {
        VStack(spacing: 0) {
            header

            Group {
                if let path = viewModel.diffPreview.path {
                    ScrollView {
                        Text(viewModel.diffPreview.content.isEmpty ? "Diff 暂无内容\n\n文件：\(path)" : viewModel.diffPreview.content)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(NativeTheme.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(12)
                    }
                } else {
                    ContentUnavailableView(
                        "选择变更以查看 Diff",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("本轮先完成 Commit 工具窗结构接线，后续任务补齐 preview 交互。")
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
