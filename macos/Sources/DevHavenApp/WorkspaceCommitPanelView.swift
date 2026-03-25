import SwiftUI
import DevHavenCore

struct WorkspaceCommitPanelView: View {
    @Bindable var viewModel: WorkspaceCommitViewModel

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Commit")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(NativeTheme.textPrimary)
                Spacer(minLength: 8)
                Text("Included \(viewModel.includedPaths.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(NativeTheme.textSecondary)
            }

            TextField("输入提交信息", text: $viewModel.commitMessage)
                .textFieldStyle(.roundedBorder)

            Text("Task 4 占位：Task 5/6 会补齐 inclusion 交互、options 与执行反馈。")
                .font(.caption)
                .foregroundStyle(NativeTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(NativeTheme.surface)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(NativeTheme.border)
                .frame(height: 1)
        }
    }
}
