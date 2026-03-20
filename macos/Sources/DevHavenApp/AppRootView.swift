import SwiftUI
import AppKit
import DevHavenCore

struct AppRootView: View {
    @Bindable var viewModel: NativeAppViewModel

    var body: some View {
        let chromePolicy = WorkspaceChromePolicy.resolve(isWorkspacePresented: viewModel.isWorkspacePresented)
        let contentVisibilityPolicy = AppRootContentVisibilityPolicy.resolve(
            isWorkspacePresented: viewModel.isWorkspacePresented
        )

        ZStack(alignment: .trailing) {
            HStack(spacing: 0) {
                if chromePolicy.showsGlobalSidebar {
                    ProjectSidebarView(viewModel: viewModel)
                        .frame(width: 240)
                        .background(NativeTheme.sidebar)
                }

                primaryContent(contentVisibilityPolicy: contentVisibilityPolicy)
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

            if let state = viewModel.worktreeInteractionState {
                WorktreeInteractionOverlayView(state: state)
                    .transition(.opacity)
            }
        }
        .background(NativeTheme.window.ignoresSafeArea())
        .background(
            InitialWindowActivationBridge()
                .allowsHitTesting(false)
        )
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

    @ViewBuilder
    private func primaryContent(contentVisibilityPolicy: AppRootContentVisibilityPolicy) -> some View {
        ZStack {
            MainContentView(viewModel: viewModel)
                .opacity(contentVisibilityPolicy.mainContentOpacity)
                .allowsHitTesting(contentVisibilityPolicy.mainContentAllowsHitTesting)
                .accessibilityHidden(contentVisibilityPolicy.mainContentOpacity == 0)

            WorkspaceShellView(viewModel: viewModel)
                .opacity(contentVisibilityPolicy.workspaceContentOpacity)
                .allowsHitTesting(contentVisibilityPolicy.workspaceContentAllowsHitTesting)
                .accessibilityHidden(contentVisibilityPolicy.workspaceContentOpacity == 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NativeTheme.window)
    }
}

private struct InitialWindowActivationBridge: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else {
                return
            }
            context.coordinator.activator.activateIfNeeded(window: AppKitWindowActivationProxy(window: window))
        }
    }

    @MainActor
    final class Coordinator {
        let activator = InitialWindowActivator(application: AppKitApplicationActivationProxy())
    }
}

@MainActor
protocol WindowActivating {
    var windowNumber: Int { get }
    func orderFrontRegardless()
    func makeKey()
}

@MainActor
protocol ApplicationActivating {
    func setRegularActivationPolicy()
    func activateIgnoringOtherApps()
}

@MainActor
final class InitialWindowActivator {
    private let application: ApplicationActivating
    private var activatedWindowNumber: Int?

    init(application: ApplicationActivating) {
        self.application = application
    }

    func activateIfNeeded(window: WindowActivating) {
        guard activatedWindowNumber != window.windowNumber else {
            return
        }
        activatedWindowNumber = window.windowNumber
        application.setRegularActivationPolicy()
        window.orderFrontRegardless()
        window.makeKey()
        application.activateIgnoringOtherApps()
    }
}

@MainActor
struct AppKitWindowActivationProxy: WindowActivating {
    let window: NSWindow

    var windowNumber: Int {
        window.windowNumber
    }

    func orderFrontRegardless() {
        window.orderFrontRegardless()
    }

    func makeKey() {
        window.makeKey()
    }
}

@MainActor
struct AppKitApplicationActivationProxy: ApplicationActivating {
    func setRegularActivationPolicy() {
        NSApp.setActivationPolicy(.regular)
    }

    func activateIgnoringOtherApps() {
        NSApp.activate(ignoringOtherApps: true)
    }
}
