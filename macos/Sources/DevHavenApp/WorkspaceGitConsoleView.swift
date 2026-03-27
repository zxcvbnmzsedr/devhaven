import SwiftUI

struct WorkspaceGitConsoleView: View {
    let repositoryPath: String

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Console")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(NativeTheme.textPrimary)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(NativeTheme.surface)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(NativeTheme.border)
                    .frame(height: 1)
            }

            ContentUnavailableView(
                "Console 尚未接入",
                systemImage: "terminal",
                description: Text("本轮先对齐 IDEA 的 Git / Log / Console 顶层结构，后续再补真实 Git Console 能力。\n\n仓库：\(repositoryPath)")
            )
            .foregroundStyle(NativeTheme.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(NativeTheme.window)
    }
}
