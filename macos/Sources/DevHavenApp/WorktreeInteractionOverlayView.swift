import SwiftUI
import DevHavenCore

struct WorktreeInteractionOverlayView: View {
    let state: WorktreeInteractionState

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)
                        .tint(.white)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("正在处理 worktree")
                            .font(.headline)
                            .foregroundStyle(NativeTheme.textPrimary)
                        Text(state.branch)
                            .font(.caption.monospaced())
                            .foregroundStyle(NativeTheme.textSecondary)
                    }
                }

                Text(state.message)
                    .font(.callout)
                    .foregroundStyle(NativeTheme.textPrimary)

                if let baseBranch = state.baseBranch, !baseBranch.isEmpty {
                    Text("基线分支：\(baseBranch)")
                        .font(.caption)
                        .foregroundStyle(NativeTheme.textSecondary)
                }

                Text(state.worktreePath)
                    .font(.caption.monospaced())
                    .foregroundStyle(NativeTheme.textSecondary)
                    .textSelection(.enabled)
            }
            .padding(18)
            .frame(width: 420, alignment: .leading)
            .background(NativeTheme.panel)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(NativeTheme.border, lineWidth: 1)
            )
            .clipShape(.rect(cornerRadius: 16))
            .shadow(color: .black.opacity(0.25), radius: 24, y: 14)
        }
        .allowsHitTesting(true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正在处理 worktree")
        .accessibilityValue(state.message)
    }
}
