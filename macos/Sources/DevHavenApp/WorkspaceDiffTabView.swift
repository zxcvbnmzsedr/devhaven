import SwiftUI
import DevHavenCore

struct WorkspaceDiffTabView: View {
    @Bindable var viewModel: WorkspaceDiffTabViewModel
    @State private var editorScrollSyncState = WorkspaceTextEditorScrollSyncState()
    @State private var editorScrollRequestState = WorkspaceTextEditorScrollRequestState()

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceDiffNavigationBarView(
                navigatorState: viewModel.viewerDescriptor?.navigatorState ?? viewModel.sessionState.navigatorState,
                viewerMode: Binding(
                    get: { viewModel.documentState.viewerMode },
                    set: { viewModel.updateViewerMode($0) }
                ),
                onRefresh: { viewModel.refresh() },
                onPreviousDifference: { viewModel.goToPreviousDifference() },
                onNextDifference: { viewModel.goToNextDifference() }
            ) {
                if viewModel.editableContentText != nil {
                    Button("保存") {
                        try? viewModel.saveEditableContent()
                    }
                    .buttonStyle(.borderless)
                }

                if viewModel.documentState.loadedMergeDocument != nil {
                    Button("接受 Ours") {
                        viewModel.applyMergeAction(.acceptOurs)
                    }
                    .buttonStyle(.borderless)

                    Button("接受 Theirs") {
                        viewModel.applyMergeAction(.acceptTheirs)
                    }
                    .buttonStyle(.borderless)

                    Button("接受 Both") {
                        viewModel.applyMergeAction(.acceptBoth)
                    }
                    .buttonStyle(.borderless)
                }
            }

            Divider()
                .overlay(NativeTheme.border)

            contentStateView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(NativeTheme.window)
        .onAppear {
            if case .idle = viewModel.documentState.loadState {
                viewModel.refresh()
            }
        }
    }

    @ViewBuilder
    private var contentStateView: some View {
        switch viewModel.documentState.loadState {
        case .idle, .loading:
            ProgressView("正在加载 Diff…")
                .tint(NativeTheme.accent)
        case let .failed(message):
            ContentUnavailableView(
                "Diff 加载失败",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
            .foregroundStyle(NativeTheme.textSecondary)
        case let .loaded(document):
            switch document {
            case let .patch(patchDocument):
                WorkspaceDiffPatchViewerView(
                    document: patchDocument,
                    viewerMode: viewModel.documentState.viewerMode,
                    paneDescriptors: viewModel.viewerDescriptor?.paneDescriptors ?? []
                )
            case let .compare(compareDocument):
                WorkspaceDiffTwoSideViewerView(
                    viewModel: viewModel,
                    document: compareDocument,
                    paneDescriptors: viewModel.viewerDescriptor?.paneDescriptors ?? [],
                    selectedDifference: viewModel.viewerDescriptor?.selectedDifference,
                    scrollSyncState: $editorScrollSyncState,
                    scrollRequestState: $editorScrollRequestState
                )
            case let .merge(mergeDocument):
                WorkspaceDiffMergeViewerView(
                    viewModel: viewModel,
                    document: mergeDocument,
                    paneDescriptors: viewModel.viewerDescriptor?.paneDescriptors ?? [],
                    selectedDifference: viewModel.viewerDescriptor?.selectedDifference,
                    scrollSyncState: $editorScrollSyncState,
                    scrollRequestState: $editorScrollRequestState
                )
            }
        }
    }
}
