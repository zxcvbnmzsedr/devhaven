import SwiftUI
import DevHavenCore

struct WorkspaceGitIdeaLogView: View {
    @Bindable var viewModel: WorkspaceGitLogViewModel
    @State private var bottomRatio = 0.62
    @State private var diffRatio = 0.68

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceGitIdeaLogToolbarView(viewModel: viewModel)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(NativeTheme.surface)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(NativeTheme.border)
                        .frame(height: 1)
                }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(NativeTheme.warning)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NativeTheme.warning.opacity(0.12))
            }

            mainContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(NativeTheme.window)
        .onAppear {
            viewModel.refresh()
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if viewModel.displayOptions.showsDetails || viewModel.displayOptions.showsDiffPreview {
            WorkspaceSplitView(
                direction: .vertical,
                ratio: bottomRatio,
                onRatioChange: { bottomRatio = $0 },
                leading: {
                    WorkspaceGitIdeaLogTableView(viewModel: viewModel)
                },
                trailing: {
                    if viewModel.displayOptions.showsDiffPreview {
                        WorkspaceSplitView(
                            direction: .vertical,
                            ratio: diffRatio,
                            onRatioChange: { diffRatio = $0 },
                            leading: {
                                WorkspaceGitIdeaLogBottomPaneView(viewModel: viewModel)
                            },
                            trailing: {
                                WorkspaceGitIdeaLogDiffPreviewView(viewModel: viewModel)
                            }
                        )
                    } else {
                        WorkspaceGitIdeaLogBottomPaneView(viewModel: viewModel)
                    }
                }
            )
        } else {
            WorkspaceGitIdeaLogTableView(viewModel: viewModel)
        }
    }
}
