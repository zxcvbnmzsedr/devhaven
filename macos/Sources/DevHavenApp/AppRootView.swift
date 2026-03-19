import SwiftUI
import DevHavenCore

struct AppRootView: View {
    @Bindable var viewModel: NativeAppViewModel

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 0) {
                ProjectSidebarView(viewModel: viewModel)
                    .frame(width: 240)
                    .background(NativeTheme.sidebar)

                MainContentView(viewModel: viewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(NativeTheme.window)
            }

            if viewModel.isDetailPanelPresented, viewModel.selectedProject != nil {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .onTapGesture {
                        viewModel.closeDetailPanel()
                    }

                ProjectDetailRootView(viewModel: viewModel)
                    .frame(width: 360)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .background(NativeTheme.window.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.18), value: viewModel.isDetailPanelPresented)
        .sheet(isPresented: $viewModel.isDashboardPresented) {
            GitDashboardView(viewModel: viewModel)
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $viewModel.isSettingsPresented) {
            SettingsView(
                settings: viewModel.snapshot.appState.settings,
                onCancel: { viewModel.hideSettings() },
                onSave: { settings in
                    viewModel.saveSettings(settings)
                    viewModel.hideSettings()
                }
            )
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $viewModel.isRecycleBinPresented) {
            RecycleBinSheetView(
                items: viewModel.recycleBinItems,
                onRestore: { item in viewModel.restoreProjectFromRecycleBin(item.path) },
                onClose: { viewModel.hideRecycleBin() }
            )
            .preferredColorScheme(.dark)
        }
        .alert("操作失败", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.dismissError() } }
        )) {
            Button("知道了", role: .cancel) {
                viewModel.dismissError()
            }
        } message: {
            Text(viewModel.errorMessage ?? "未知错误")
        }
        .task {
            guard !viewModel.hasLoadedInitialData else {
                return
            }
            viewModel.load()
        }
    }
}
