import SwiftUI
import DevHavenCore

struct WorkspaceRootView: View {
    @Bindable var viewModel: NativeAppViewModel
    let terminalStoreRegistry: WorkspaceTerminalStoreRegistry
    @State private var sidebarWidth: CGFloat = WorkspaceSidebarLayoutPolicy.defaultSidebarWidth

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width

            WorkspaceSplitView(
                direction: .horizontal,
                ratio: WorkspaceSidebarLayoutPolicy.sidebarRatio(
                    for: sidebarWidth,
                    totalWidth: totalWidth
                ),
                onRatioChange: { ratio in
                    sidebarWidth = WorkspaceSidebarLayoutPolicy.sidebarWidth(
                        for: ratio,
                        totalWidth: totalWidth
                    )
                },
                onRatioChangeEnded: { ratio in
                    let committedWidth = WorkspaceSidebarLayoutPolicy.sidebarWidth(
                        for: ratio,
                        totalWidth: totalWidth
                    )
                    sidebarWidth = committedWidth
                    persistSidebarWidth(committedWidth)
                },
                minLeadingSize: WorkspaceSidebarLayoutPolicy.minimumSidebarWidth,
                minTrailingSize: WorkspaceSidebarLayoutPolicy.minimumWorkspaceContentWidth,
                onEqualize: {
                    sidebarWidth = WorkspaceSidebarLayoutPolicy.defaultSidebarWidth
                    persistSidebarWidth(WorkspaceSidebarLayoutPolicy.defaultSidebarWidth)
                }
            ) {
                WorkspaceProjectSidebarHostView(viewModel: viewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } trailing: {
                WorkspaceChromeContainerView(viewModel: viewModel) {
                    WorkspaceShellView(
                        viewModel: viewModel,
                        terminalStoreRegistry: terminalStoreRegistry
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .onAppear {
                syncSidebarWidth(totalWidth: totalWidth)
            }
            .onChange(of: viewModel.workspaceSidebarWidth) { _, _ in
                syncSidebarWidth(totalWidth: totalWidth)
            }
            .onChange(of: totalWidth) { _, _ in
                syncSidebarWidth(totalWidth: totalWidth)
            }
        }
        .background(NativeTheme.window)
    }

    private func syncSidebarWidth(totalWidth: CGFloat) {
        sidebarWidth = WorkspaceSidebarLayoutPolicy.clampSidebarWidth(
            CGFloat(viewModel.workspaceSidebarWidth),
            totalWidth: totalWidth
        )
    }

    private func persistSidebarWidth(_ width: CGFloat) {
        let persistedWidth = Double(width.rounded())
        viewModel.updateWorkspaceSidebarWidth(persistedWidth)
    }
}
