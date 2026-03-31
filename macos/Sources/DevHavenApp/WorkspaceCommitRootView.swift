import SwiftUI
import DevHavenCore

struct WorkspaceCommitRootView: View {
    @Bindable var viewModel: WorkspaceCommitViewModel
    let onSyncDiffIfNeeded: (WorkspaceCommitChange) -> Void
    let onOpenDiff: (WorkspaceCommitChange) -> Void
    @State private var topAreaRatio: Double = 0.7

    var body: some View {
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
}
