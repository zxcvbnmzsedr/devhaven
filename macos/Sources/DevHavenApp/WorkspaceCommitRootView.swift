import SwiftUI
import DevHavenCore

struct WorkspaceCommitRootView: View {
    @Bindable var viewModel: WorkspaceCommitViewModel
    let onSyncDiffIfNeeded: (WorkspaceCommitChange) -> Void
    let onOpenDiff: (WorkspaceCommitChange) -> Void
    @State private var topAreaRatio: Double = 0.7

    var body: some View {
        VStack(spacing: 0) {
            repositoryHeader
            WorkspaceSplitView(
                direction: .vertical,
                ratio: topAreaRatio,
                onRatioChange: { topAreaRatio = $0 },
                minLeadingSize: 180,
                minTrailingSize: 220,
                onEqualize: { topAreaRatio = 0.7 }
            ) {
                WorkspaceCommitChangesBrowserView(
                    viewModel: viewModel,
                    onSyncDiffIfNeeded: onSyncDiffIfNeeded,
                    onOpenDiff: onOpenDiff
                )
            } trailing: {
                WorkspaceCommitPanelView(viewModel: viewModel)
            }
        }
        .task(id: viewModel.repositoryContext.executionPath) {
            viewModel.refreshChangesSnapshot()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    return
                }
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run {
                    viewModel.refreshChangesSnapshot()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NativeTheme.window)
    }

    private var repositoryHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Commit")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(NativeTheme.textPrimary)
                if viewModel.repositoryFamilies.count > 1 {
                    Text(viewModel.selectedRepositoryFamilyDisplayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NativeTheme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(NativeTheme.elevated)
                        .clipShape(.capsule)
                }
                Spacer(minLength: 8)
            }

            Text(viewModel.selectedExecutionDisplayName)
                .font(.caption.weight(.medium))
                .foregroundStyle(NativeTheme.textSecondary)
            Text(viewModel.repositoryContext.executionPath)
                .font(.caption2.monospaced())
                .foregroundStyle(NativeTheme.textSecondary)
                .textSelection(.enabled)
                .lineLimit(1)
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
