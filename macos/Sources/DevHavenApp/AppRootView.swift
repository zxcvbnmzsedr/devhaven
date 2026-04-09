import SwiftUI
import AppKit
import Combine
import DevHavenCore

struct AppRootView: View {
    @Bindable var viewModel: NativeAppViewModel
    @ObservedObject var updateController: DevHavenUpdateController
    @ObservedObject var quitGuard: AppQuitGuard
    @Environment(\.scenePhase) private var scenePhase

    init(
        viewModel: NativeAppViewModel,
        updateController: DevHavenUpdateController = DevHavenUpdateController(),
        quitGuard: AppQuitGuard = AppQuitGuard()
    ) {
        self.viewModel = viewModel
        self.updateController = updateController
        self.quitGuard = quitGuard
    }

    var body: some View {
        let chromePolicy = WorkspaceChromePolicy.resolve(isWorkspacePresented: viewModel.isWorkspacePresented)
        let contentVisibilityPolicy = AppRootContentVisibilityPolicy.resolve(
            isWorkspacePresented: viewModel.isWorkspacePresented
        )
        let projectDetailPresentation = AppRootProjectDetailPresentationPolicy.resolve(
            isWorkspacePresented: viewModel.isWorkspacePresented,
            selectedProjectExists: viewModel.selectedProject != nil,
            isDetailPanelRequested: viewModel.isDetailPanelPresented
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

                if projectDetailPresentation.showsPersistentSidebar {
                    ProjectDetailRootView(
                        viewModel: viewModel,
                        showsCloseButton: false,
                        onClose: {}
                    )
                        .frame(width: 360)
                }
            }

            if projectDetailPresentation.showsDismissableOverlay {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .onTapGesture {
                        DetailPanelCloseAction.perform(for: viewModel)
                    }

                ProjectDetailRootView(
                    viewModel: viewModel,
                    showsCloseButton: true,
                    onClose: { DetailPanelCloseAction.perform(for: viewModel) }
                )
                    .frame(width: 360)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            if let state = viewModel.worktreeInteractionState {
                WorktreeInteractionOverlayView(state: state)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .top) {
            if quitGuard.toastMessage != nil || viewModel.workspaceToastMessage != nil {
                VStack(spacing: 8) {
                    if let toastMessage = quitGuard.toastMessage {
                        AppQuitToastView(message: toastMessage)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    if let workspaceToastMessage = viewModel.workspaceToastMessage {
                        AppQuitToastView(message: workspaceToastMessage)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.top, 18)
            }
        }
        .background(NativeTheme.window.ignoresSafeArea())
        .background(
            MainWindowCloseShortcutBridge(onHandleCloseShortcut: handleMainWindowCloseShortcut)
                .allowsHitTesting(false)
        )
        .background(
            MainWindowCloseConfirmationBridge()
                .allowsHitTesting(false)
        )
        .background(
            InitialWindowActivationBridge()
                .allowsHitTesting(false)
        )
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.18), value: projectDetailPresentation)
        .animation(.easeInOut(duration: 0.16), value: quitGuard.toastMessage != nil)
        .animation(.easeInOut(duration: 0.16), value: viewModel.workspaceToastMessage != nil)
        .sheet(isPresented: $viewModel.isDashboardPresented) {
            GitDashboardView(viewModel: viewModel)
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $viewModel.isSettingsPresented) {
            SettingsView(
                settings: viewModel.snapshot.appState.settings,
                initialCategory: viewModel.requestedSettingsSection,
                onCancel: { viewModel.hideSettings() },
                onSave: { settings in
                    viewModel.saveSettings(settings)
                    viewModel.hideSettings()
                },
                updateSupportDescription: updateController.supportDescription,
                updateDiagnostics: updateController.diagnosticsText,
                isUpdaterSupported: updateController.isSupported,
                supportsAutomaticUpdates: updateController.supportsAutomaticUpdates,
                canOpenUpdateDownloadPage: updateController.canOpenDownloadPage,
                onCheckForUpdates: { updateController.checkForUpdates() },
                onOpenUpdateDownloadPage: { updateController.openDownloadPage() },
                onCopyUpdateDiagnostics: { updateController.copyDiagnosticsToPasteboard() }
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
        .onChange(of: viewModel.snapshot.appState.settings) { _, settings in
            updateController.apply(settings: settings)
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .inactive, .background:
                viewModel.flushWorkspaceRestoreSnapshotNow()
            default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            viewModel.flushWorkspaceRestoreSnapshotNow()
        }
        .task {
            guard !viewModel.hasLoadedInitialData else {
                updateController.apply(settings: viewModel.snapshot.appState.settings)
                return
            }
            viewModel.load()
            updateController.apply(settings: viewModel.snapshot.appState.settings)
        }
    }

    @ViewBuilder
    private func primaryContent(contentVisibilityPolicy: AppRootContentVisibilityPolicy) -> some View {
        ZStack {
            MainContentView(viewModel: viewModel)
                .opacity(contentVisibilityPolicy.mainContentOpacity)
                .allowsHitTesting(contentVisibilityPolicy.mainContentAllowsHitTesting)
                .accessibilityHidden(contentVisibilityPolicy.mainContentOpacity == 0)

            WorkspaceRootView(viewModel: viewModel)
                .opacity(contentVisibilityPolicy.workspaceContentOpacity)
                .allowsHitTesting(contentVisibilityPolicy.workspaceContentAllowsHitTesting)
                .accessibilityHidden(contentVisibilityPolicy.workspaceContentOpacity == 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NativeTheme.window)
    }

    private func handleMainWindowCloseShortcut() -> Bool {
        let action = MainWindowCloseShortcutPlanner().action(for: mainWindowCloseShortcutContext)
        switch action {
        case .hideDashboard:
            viewModel.hideDashboard()
            return true
        case .hideSettings:
            viewModel.hideSettings()
            return true
        case .hideRecycleBin:
            viewModel.hideRecycleBin()
            return true
        case .hideDetailPanel:
            DetailPanelCloseAction.perform(for: viewModel)
            return true
        case let .closePane(paneID):
            viewModel.closeWorkspacePane(paneID)
            return true
        case let .closeEditorTab(tabID):
            viewModel.closeWorkspaceEditorTab(tabID)
            return true
        case let .closeDiffTab(tabID):
            viewModel.closeWorkspaceDiffTab(tabID)
            return true
        case let .closeTab(tabID):
            viewModel.closeWorkspaceTab(tabID)
            return true
        case .exitWorkspace:
            viewModel.exitWorkspace()
            return true
        case .closeWindow:
            return false
        }
    }

    private var mainWindowCloseShortcutContext: MainWindowCloseShortcutContext {
        MainWindowCloseShortcutContext(
            isDashboardPresented: viewModel.isDashboardPresented,
            isSettingsPresented: viewModel.isSettingsPresented,
            isRecycleBinPresented: viewModel.isRecycleBinPresented,
            isDetailPanelPresented: AppRootProjectDetailPresentationPolicy.resolve(
                isWorkspacePresented: viewModel.isWorkspacePresented,
                selectedProjectExists: viewModel.selectedProject != nil,
                isDetailPanelRequested: viewModel.isDetailPanelPresented
            ).showsDismissableOverlay,
            workspace: activeWorkspaceCloseShortcutContext
        )
    }

    private var activeWorkspaceCloseShortcutContext: MainWindowCloseShortcutWorkspaceContext? {
        guard viewModel.isWorkspacePresented,
              let workspace = viewModel.activeWorkspaceController
        else {
            return nil
        }

        let selectedTab = workspace.selectedTab
        let selectedPaneID = workspace.selectedPane?.id ?? selectedTab?.focusedPaneId
        let selectedTabID = workspace.selectedTabId ?? selectedTab?.id

        return MainWindowCloseShortcutWorkspaceContext(
            selectedPaneID: selectedPaneID,
            selectedTabID: selectedTabID,
            selectedEditorTabID: viewModel.activeWorkspaceSelectedEditorTabID,
            selectedDiffTabID: viewModel.activeWorkspaceSelectedDiffTabID,
            selectedTabPaneCount: selectedTab?.leaves.count ?? 0,
            tabCount: workspace.tabCount
        )
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

private struct MainWindowCloseShortcutBridge: NSViewRepresentable {
    let onHandleCloseShortcut: () -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.onHandleCloseShortcut = onHandleCloseShortcut
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.onHandleCloseShortcut = onHandleCloseShortcut
    }

    @MainActor
    final class Coordinator {
        var onHandleCloseShortcut: () -> Bool = { false }
        private var localMonitor: Any?

        init() {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else {
                    return event
                }
                guard Self.matchesCloseShortcut(event) else {
                    return event
                }
                return self.onHandleCloseShortcut() ? nil : event
            }
        }

        private static func matchesCloseShortcut(_ event: NSEvent) -> Bool {
            guard event.type == .keyDown else {
                return false
            }
            let relevantModifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
            guard relevantModifiers == .command else {
                return false
            }
            return event.charactersIgnoringModifiers?.lowercased() == "w"
        }

        isolated deinit {
            if let localMonitor {
                NSEvent.removeMonitor(localMonitor)
            }
        }
    }
}

enum MainWindowCloseShortcutAction: Equatable {
    case hideDashboard
    case hideSettings
    case hideRecycleBin
    case hideDetailPanel
    case closePane(String)
    case closeEditorTab(String)
    case closeDiffTab(String)
    case closeTab(String)
    case exitWorkspace
    case closeWindow
}

struct MainWindowCloseShortcutWorkspaceContext: Equatable {
    var selectedPaneID: String?
    var selectedTabID: String?
    var selectedEditorTabID: String? = nil
    var selectedDiffTabID: String? = nil
    var selectedTabPaneCount: Int
    var tabCount: Int
}

struct MainWindowCloseShortcutContext: Equatable {
    var isDashboardPresented: Bool
    var isSettingsPresented: Bool
    var isRecycleBinPresented: Bool
    var isDetailPanelPresented: Bool
    var workspace: MainWindowCloseShortcutWorkspaceContext?
}

struct MainWindowCloseShortcutPlanner {
    func action(for context: MainWindowCloseShortcutContext) -> MainWindowCloseShortcutAction {
        if context.isSettingsPresented {
            return .hideSettings
        }
        if context.isDashboardPresented {
            return .hideDashboard
        }
        if context.isRecycleBinPresented {
            return .hideRecycleBin
        }
        if context.isDetailPanelPresented {
            return .hideDetailPanel
        }
        guard let workspace = context.workspace else {
            return .closeWindow
        }
        if let editorTabID = workspace.selectedEditorTabID {
            return .closeEditorTab(editorTabID)
        }
        if let diffTabID = workspace.selectedDiffTabID {
            return .closeDiffTab(diffTabID)
        }
        if workspace.selectedTabPaneCount > 1,
           let paneID = workspace.selectedPaneID {
            return .closePane(paneID)
        }
        if workspace.tabCount > 1,
           let tabID = workspace.selectedTabID {
            return .closeTab(tabID)
        }
        return .exitWorkspace
    }
}

struct AppRootProjectDetailPresentationPolicy: Equatable {
    var showsPersistentSidebar: Bool
    var showsDismissableOverlay: Bool

    static func resolve(
        isWorkspacePresented: Bool,
        selectedProjectExists: Bool,
        isDetailPanelRequested: Bool
    ) -> AppRootProjectDetailPresentationPolicy {
        guard selectedProjectExists else {
            return AppRootProjectDetailPresentationPolicy(
                showsPersistentSidebar: false,
                showsDismissableOverlay: false
            )
        }

        if !isWorkspacePresented {
            return AppRootProjectDetailPresentationPolicy(
                showsPersistentSidebar: true,
                showsDismissableOverlay: false
            )
        }

        return AppRootProjectDetailPresentationPolicy(
            showsPersistentSidebar: false,
            showsDismissableOverlay: isDetailPanelRequested
        )
    }
}

private struct MainWindowCloseConfirmationBridge: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else {
                context.coordinator.detach()
                return
            }
            if window.identifier == nil {
                window.identifier = NSUserInterfaceItemIdentifier("main")
            }
            context.coordinator.attach(to: window)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSWindowDelegate {
        private let handler = MainWindowCloseConfirmationHandler(prompt: AppKitMainWindowClosePrompt())
        private weak var trackedWindow: NSWindow?
        private weak var forwardedDelegate: (any NSWindowDelegate)?

        func attach(to window: NSWindow) {
            handler.track(windowNumber: window.windowNumber)

            let delegateNeedsRefresh = trackedWindow !== window || window.delegate !== self
            guard delegateNeedsRefresh else {
                return
            }
            detach()
            trackedWindow = window
            forwardedDelegate = window.delegate
            window.delegate = self
        }

        func detach() {
            guard let trackedWindow else {
                forwardedDelegate = nil
                return
            }
            if trackedWindow.delegate === self {
                trackedWindow.delegate = forwardedDelegate
            }
            self.trackedWindow = nil
            forwardedDelegate = nil
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard handler.shouldAllowClose(windowNumber: sender.windowNumber) else {
                return false
            }
            return forwardedDelegate?.windowShouldClose?(sender) ?? true
        }

        isolated deinit {
            detach()
        }
    }
}

@MainActor
protocol MainWindowClosePrompting {
    func confirmCloseMainWindow() -> Bool
}

struct MainWindowClosePromptCopy: Equatable {
    var title: String
    var informativeText: String
    var confirmButtonTitle: String
    var cancelButtonTitle: String
}

@MainActor
final class MainWindowCloseConfirmationHandler {
    private let prompt: any MainWindowClosePrompting
    private var trackedWindowNumber: Int?

    init(prompt: any MainWindowClosePrompting) {
        self.prompt = prompt
    }

    func track(windowNumber: Int) {
        trackedWindowNumber = windowNumber
    }

    func shouldAllowClose(windowNumber: Int) -> Bool {
        guard windowNumber == trackedWindowNumber else {
            return true
        }
        return prompt.confirmCloseMainWindow()
    }
}

@MainActor
struct AppKitMainWindowClosePrompt: MainWindowClosePrompting {
    static let copy = MainWindowClosePromptCopy(
        title: "关闭 DevHaven？",
        informativeText: "这会关闭主窗口。",
        confirmButtonTitle: "关闭窗口",
        cancelButtonTitle: "取消"
    )

    func confirmCloseMainWindow() -> Bool {
        let copy = Self.copy
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = copy.title
        alert.informativeText = copy.informativeText
        alert.addButton(withTitle: copy.confirmButtonTitle)
        alert.addButton(withTitle: copy.cancelButtonTitle)
        return alert.runModal() == .alertFirstButtonReturn
    }
}
