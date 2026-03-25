import SwiftUI
import DevHavenCore

struct WorkspaceGitRootView: View {
    @Bindable var viewModel: WorkspaceGitViewModel
    @State private var sidebarRatio = 0.22

    var body: some View {
        Group {
            if viewModel.section == .log {
                WorkspaceGitIdeaLogView(viewModel: viewModel.logViewModel)
            } else {
                nonLogContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(NativeTheme.window)
        .onAppear {
            if viewModel.section == .log {
                viewModel.logViewModel.refresh()
            } else {
                viewModel.refreshForCurrentSection()
            }
        }
    }

    private var nonLogContent: some View {
        VStack(spacing: 0) {
            WorkspaceGitToolbarView(viewModel: viewModel)
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
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NativeTheme.warning.opacity(0.12))
            }

            WorkspaceSplitView(
                direction: .horizontal,
                ratio: sidebarRatio,
                onRatioChange: { sidebarRatio = $0 },
                leading: {
                    WorkspaceGitSidebarView(
                        viewModel: viewModel,
                        showsExecutionWorktreeSelector: true
                    )
                    .background(NativeTheme.sidebar)
                },
                trailing: {
                    switch viewModel.section {
                    case .log:
                        EmptyView()
                    case .changes:
                        WorkspaceGitChangesView(viewModel: viewModel)
                    case .branches:
                        WorkspaceGitBranchesView(viewModel: viewModel)
                    case .operations:
                        WorkspaceGitOperationsView(viewModel: viewModel)
                    }
                }
            )
        }
    }
}
