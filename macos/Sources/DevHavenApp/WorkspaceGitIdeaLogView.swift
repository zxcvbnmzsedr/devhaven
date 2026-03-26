import SwiftUI
import DevHavenCore

struct WorkspaceGitIdeaLogView: View {
    @Bindable var viewModel: WorkspaceGitLogViewModel
    let onOpenDiff: (WorkspaceGitCommitFileChange) -> Void
    @State private var isBranchesPanelVisible = true
    @State private var branchesPanelRatio = 0.20
    @State private var rightSidebarRatio = 0.76

    var body: some View {
        HStack(spacing: 0) {
            branchesControlStrip

            if isBranchesPanelVisible {
                WorkspaceSplitView(
                    direction: .horizontal,
                    ratio: branchesPanelRatio,
                    onRatioChange: { branchesPanelRatio = $0 },
                    leading: {
                        WorkspaceGitIdeaLogBranchesPanelView(
                            viewModel: viewModel,
                            isVisible: $isBranchesPanelVisible
                        )
                        .background(NativeTheme.sidebar)
                    },
                    trailing: {
                        mainFrameContent
                    }
                )
            } else {
                mainFrameContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(NativeTheme.window)
        .onAppear {
            viewModel.refresh()
        }
    }

    private var branchesControlStrip: some View {
        VStack(spacing: 10) {
            Button {
                isBranchesPanelVisible.toggle()
            } label: {
                Image(systemName: isBranchesPanelVisible ? "chevron.left" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NativeTheme.textPrimary)
                    .frame(width: 28, height: 28)
                    .background(NativeTheme.elevated)
                    .clipShape(.rect(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.caption)
                .foregroundStyle(NativeTheme.textSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(NativeTheme.surface)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(NativeTheme.border)
                .frame(width: 1)
        }
    }

    @ViewBuilder
    private var mainFrameContent: some View {
        WorkspaceSplitView(
            direction: .horizontal,
            ratio: rightSidebarRatio,
            onRatioChange: { rightSidebarRatio = $0 },
            leading: {
                mainFramePrimaryColumn
            },
            trailing: {
                WorkspaceGitIdeaLogRightSidebarView(viewModel: viewModel, onOpenDiff: onOpenDiff)
            }
        )
    }

    @ViewBuilder
    private var mainFramePrimaryColumn: some View {
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

            WorkspaceGitIdeaLogTableView(viewModel: viewModel)
        }
    }
}
