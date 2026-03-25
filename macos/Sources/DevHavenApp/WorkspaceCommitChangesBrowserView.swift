import SwiftUI
import DevHavenCore

struct WorkspaceCommitChangesBrowserView: View {
    @Bindable var viewModel: WorkspaceCommitViewModel

    var body: some View {
        VStack(spacing: 0) {
            header

            Group {
                if let snapshot = viewModel.changesSnapshot, !snapshot.changes.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(snapshot.changes) { change in
                                changeRow(change)
                            }
                        }
                        .padding(12)
                    }
                } else {
                    ContentUnavailableView(
                        "暂无变更",
                        systemImage: "checkmark.circle",
                        description: Text("当前工作区没有可提交变更。")
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
            Text("Changes")
                .font(.callout.weight(.semibold))
                .foregroundStyle(NativeTheme.textPrimary)
            Spacer(minLength: 8)
            Text("\(viewModel.changesSnapshot?.changes.count ?? 0)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(NativeTheme.textSecondary)
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

    private func changeRow(_ change: WorkspaceCommitChange) -> some View {
        HStack(spacing: 8) {
            Image(systemName: viewModel.includedPaths.contains(change.path) ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(viewModel.includedPaths.contains(change.path) ? NativeTheme.accent : NativeTheme.textSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(change.path)
                    .font(.callout.monospaced())
                    .foregroundStyle(NativeTheme.textPrimary)
                Text(change.group.rawValue.uppercased())
                    .font(.caption2.monospaced())
                    .foregroundStyle(NativeTheme.textSecondary)
            }
            Spacer(minLength: 8)
        }
        .padding(10)
        .background(NativeTheme.elevated)
        .clipShape(.rect(cornerRadius: 8))
    }
}
