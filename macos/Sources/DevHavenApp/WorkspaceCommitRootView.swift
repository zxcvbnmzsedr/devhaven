import SwiftUI
import DevHavenCore

struct WorkspaceCommitRootView: View {
    @Bindable var viewModel: WorkspaceCommitViewModel
    let onSyncDiffIfNeeded: (WorkspaceCommitChange) -> Void
    let onOpenDiff: (WorkspaceCommitChange) -> Void
    @State private var topAreaRatio: Double = 0.7
    private let autoRefreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

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
        .onAppear {
            viewModel.refreshChangesSnapshot()
        }
        .onReceive(autoRefreshTimer) { _ in
            viewModel.refreshChangesSnapshot()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NativeTheme.window)
    }
}
