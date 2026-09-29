import SwiftUI
import AppKit
import Bonsplit
import CmuxUpdater
import CmuxAppKitSupportUI
import Combine

/// The cmux workspace composition root exposed for hosts that embed cmux.
///
/// This deliberately builds the same `ContentView` used by the cmux desktop
/// app.  The host supplies only the initial working directory; sidebar,
/// workspaces, tabs, panes, notifications, and configuration remain cmux-owned.
@MainActor
public struct CmuxEmbeddedRootView: View {
    private let windowId: UUID
    private let updateViewModel: UpdateStateModel
    private let titlebarControlsLayoutModel: TitlebarControlsLayoutModel
    private let sessionDragRegistry: SessionDragRegistry
    private let tabDragTransferRegistry: TabDragTransferRegistry

    @StateObject private var tabManager: TabManager
    @StateObject private var notificationStore: TerminalNotificationStore
    @StateObject private var sidebarState: SidebarState
    @StateObject private var sidebarSelectionState: SidebarSelectionState
    @StateObject private var fileExplorerState: FileExplorerState
    @StateObject private var cmuxConfigStore: CmuxConfigStore

    public init(
        initialWorkingDirectory: String? = nil,
        initialWorkspaceTitle: String? = nil
    ) {
        self.init(
            initialWorkingDirectory: initialWorkingDirectory,
            initialWorkspaceTitle: initialWorkspaceTitle,
            onTabManagerCreated: { _ in }
        )
    }

    init(
        initialWorkingDirectory: String?,
        initialWorkspaceTitle: String?,
        onTabManagerCreated: (TabManager) -> Void
    ) {
        let windowId = UUID()
        let tabDragTransferRegistry = TabDragTransferRegistry()
        let tabManager = TabManager(
            initialWorkspaceTitle: initialWorkspaceTitle,
            initialWorkingDirectory: initialWorkingDirectory,
            tabDragTransferRegistry: tabDragTransferRegistry
        )
        tabManager.windowId = windowId
        tabManager.isEmbeddedInHost = true
        onTabManagerCreated(tabManager)

        let configStore = CmuxConfigStore()
        configStore.wireDirectoryTracking(tabManager: tabManager)
        configStore.loadAll()

        self.windowId = windowId
        self.updateViewModel = UpdateStateModel()
        self.titlebarControlsLayoutModel = TitlebarControlsLayoutModel()
        self.sessionDragRegistry = SessionDragRegistry()
        self.tabDragTransferRegistry = tabDragTransferRegistry
        _tabManager = StateObject(wrappedValue: tabManager)
        _notificationStore = StateObject(wrappedValue: TerminalNotificationStore.shared)
        _sidebarState = StateObject(wrappedValue: SidebarState())
        _sidebarSelectionState = StateObject(wrappedValue: SidebarSelectionState())
        _fileExplorerState = StateObject(wrappedValue: FileExplorerState())
        _cmuxConfigStore = StateObject(wrappedValue: configStore)
    }

    public var body: some View {
        ContentView(
            updateViewModel: updateViewModel,
            windowId: windowId,
            titlebarControlsLayoutModel: titlebarControlsLayoutModel,
            devicesModel: nil
        )
        .environmentObject(tabManager)
        .environmentObject(notificationStore)
        .environmentObject(sidebarState)
        .environmentObject(sidebarSelectionState)
        .environmentObject(fileExplorerState)
        .environmentObject(cmuxConfigStore)
        .environment(\.sessionDragRegistry, sessionDragRegistry)
        .environment(\.tabDragTransferRegistry, tabDragTransferRegistry)
        .cmuxFontMagnificationEnvironment()
    }
}

/// Buttons inside a nested hosting view do not receive AppKit mouse-downs in
/// the host window's full-size titlebar. Keep their SwiftUI actions for AX and
/// keyboard access, and register their exact frames for the embedded host's
/// titlebar event monitor.
@MainActor
struct CmuxEmbeddedHeaderActionRegion: NSViewRepresentable {
    let action: () -> Void

    final class RegionView: NSView {
        var action: () -> Void = {}

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                CmuxEmbeddedHeaderActionRegion.regions.remove(self)
            } else {
                CmuxEmbeddedHeaderActionRegion.regions.add(self)
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override var mouseDownCanMoveWindow: Bool { false }
    }

    private static let regions = NSHashTable<RegionView>.weakObjects()

    static func performActionIfHit(in window: NSWindow, at point: NSPoint) -> Bool {
        for region in regions.allObjects where region.window === window {
            guard !region.isHiddenOrHasHiddenAncestor,
                  region.bounds.contains(region.convert(point, from: nil)) else { continue }
            region.action()
            return true
        }
        return false
    }

    func makeNSView(context: Context) -> RegionView {
        let view = RegionView(frame: .zero)
        view.action = action
        return view
    }

    func updateNSView(_ nsView: RegionView, context: Context) {
        nsView.action = action
    }
}

/// C ABI entry point used by DevHaven so it can host cmux without importing
/// cmux's private Swift package graph into its own SwiftPM build.
@_cdecl("cmux_embedded_host_view_create")
@MainActor
public func cmuxEmbeddedHostViewCreate(_ workingDirectory: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer {
    let directory = workingDirectory.map { String(cString: $0) }
    let host = CmuxEmbeddedHostView(workingDirectory: directory)
    return Unmanaged.passRetained(host).toOpaque()
}

/// Releases a host view previously created by ``cmuxEmbeddedHostViewCreate``.
@_cdecl("cmux_embedded_host_view_destroy")
@MainActor
public func cmuxEmbeddedHostViewDestroy(_ hostPointer: UnsafeMutableRawPointer?) {
    guard let hostPointer else { return }
    let host = Unmanaged<CmuxEmbeddedHostView>.fromOpaque(hostPointer).takeUnretainedValue()
    host.tearDown()
    Unmanaged<CmuxEmbeddedHostView>.fromOpaque(hostPointer).release()
}

/// Detaches the embedded view from DevHaven's window without closing its tabs.
@_cdecl("cmux_embedded_host_view_suspend")
@MainActor
public func cmuxEmbeddedHostViewSuspend(_ hostPointer: UnsafeMutableRawPointer?) {
    guard let hostPointer else { return }
    Unmanaged<CmuxEmbeddedHostView>.fromOpaque(hostPointer)
        .takeUnretainedValue()
        .suspendWindowIntegration()
}

@_cdecl("cmux_embedded_projects_update")
@MainActor
public func cmuxEmbeddedProjectsUpdate(_ hostPointer: UnsafeMutableRawPointer?, _ json: UnsafePointer<CChar>?) {
    guard let hostPointer, let json else { return }
    Unmanaged<CmuxEmbeddedHostView>.fromOpaque(hostPointer)
        .takeUnretainedValue()
        .updateProjects(json: String(cString: json))
}

@_cdecl("cmux_embedded_host_view_close_current_panel")
@MainActor
public func cmuxEmbeddedHostViewCloseCurrentPanel(_ hostPointer: UnsafeMutableRawPointer?) {
    guard let hostPointer else { return }
    Unmanaged<CmuxEmbeddedHostView>.fromOpaque(hostPointer)
        .takeUnretainedValue()
        .closeCurrentPanel()
}

@MainActor
private final class CmuxEmbeddedHostView: NSView {
    private struct Project: Decodable {
        let path: String
        let name: String
    }

    private struct ProjectsSnapshot: Decodable {
        let projects: [Project]
        let activePath: String?
    }

    private let hostingView: EmbeddedCmuxHostingView
    private let tabManager: TabManager
    private var projectWorkspaceIds: [String: UUID] = [:]
    private var projectPathsByWorkspaceId: [UUID: String] = [:]
    private var subscriptions = Set<AnyCancellable>()
    private var isSynchronizingProjects = false
    private var originalWindowState: OriginalWindowState?
    private var titlebarDragMonitor: Any?
    private var needsPortalRebind = false
    private var didTearDown = false

    private struct OriginalWindowState {
        let identifier: NSUserInterfaceItemIdentifier?
        let isRestorable: Bool
        let isMovable: Bool
        let isMovableByWindowBackground: Bool
        let titleVisibility: NSWindow.TitleVisibility
        let titlebarAppearsTransparent: Bool
        let hasFullSizeContentView: Bool
        let backgroundColor: NSColor
        let isOpaque: Bool
    }

    init(workingDirectory: String?) {
        var createdManager: TabManager?
        let rootView = CmuxEmbeddedRootView(
            initialWorkingDirectory: workingDirectory,
            initialWorkspaceTitle: nil,
            onTabManagerCreated: { createdManager = $0 }
        )
        tabManager = createdManager!
        hostingView = EmbeddedCmuxHostingView(rootView: rootView)
        super.init(frame: .zero)
        if let workingDirectory, let firstWorkspace = tabManager.tabs.first {
            projectWorkspaceIds[workingDirectory] = firstWorkspace.id
            projectPathsByWorkspaceId[firstWorkspace.id] = workingDirectory
        }
        tabManager.selectedTabIdPublisher
            .sink { [weak self] workspaceId in
                guard let self, !self.isSynchronizingProjects,
                      let workspaceId,
                      let path = self.projectPathsByWorkspaceId[workspaceId] else { return }
                NotificationCenter.default.post(
                    name: Notification.Name("DevHaven.CmuxEmbedded.ActivateProject"),
                    object: path
                )
            }
            .store(in: &subscriptions)
        tabManager.tabsPublisher
            .sink { [weak self] tabs in
                guard let self, !self.isSynchronizingProjects else { return }
                let liveIds = Set(tabs.map(\.id))
                for (path, id) in Array(self.projectWorkspaceIds) where !liveIds.contains(id) {
                    self.projectWorkspaceIds.removeValue(forKey: path)
                    self.projectPathsByWorkspaceId.removeValue(forKey: id)
                    NotificationCenter.default.post(
                        name: Notification.Name("DevHaven.CmuxEmbedded.ClosedProject"),
                        object: path
                    )
                }
                if tabs.contains(where: { self.projectPathsByWorkspaceId[$0.id] == nil }) {
                    DispatchQueue.main.async { [weak self] in
                        guard let self, !self.isSynchronizingProjects else { return }
                        for workspace in self.tabManager.tabs where self.projectPathsByWorkspaceId[workspace.id] == nil {
                            if self.tabManager.tabs.count > 1 {
                                self.tabManager.closeWorkspace(workspace, recordHistory: false)
                            }
                        }
                        NotificationCenter.default.post(
                            name: Notification.Name("DevHaven.CmuxEmbedded.OpenProjectPicker"),
                            object: nil
                        )
                    }
                }
            }
            .store(in: &subscriptions)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if let currentWindow = window, newWindow !== currentWindow {
            suspendWindowIntegration()
        }
        if let newWindow, originalWindowState == nil {
            originalWindowState = OriginalWindowState(
                identifier: newWindow.identifier,
                isRestorable: newWindow.isRestorable,
                isMovable: newWindow.isMovable,
                isMovableByWindowBackground: newWindow.isMovableByWindowBackground,
                titleVisibility: newWindow.titleVisibility,
                titlebarAppearsTransparent: newWindow.titlebarAppearsTransparent,
                hasFullSizeContentView: newWindow.styleMask.contains(.fullSizeContentView),
                backgroundColor: newWindow.backgroundColor,
                isOpaque: newWindow.isOpaque
            )
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        // cmux fills the host's titlebar. AppKit owns mouse-down delivery in
        // that band, so leave native titlebar movement enabled while keeping
        // all content below it non-draggable.
        CmuxEmbeddedWindowDragPolicy.markEmbedded(window)
        window.isMovableByWindowBackground = false
        window.isMovable = true
        window.titleVisibility = .hidden
        installTitlebarDragMonitor()
        if needsPortalRebind {
            needsPortalRebind = false
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.window === window, !self.didTearDown else { return }
                self.tabManager.objectWillChange.send()
            }
        }
#if DEBUG
        cmuxDebugLog("embedded.window.attached origin=\(NSStringFromPoint(window.frame.origin)) movable=\(window.isMovable)")
        NotificationCenter.default.removeObserver(self, name: NSWindow.didMoveNotification, object: window)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidMove(_:)),
            name: NSWindow.didMoveNotification,
            object: window
        )
#endif
    }

#if DEBUG
    @objc private func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        cmuxDebugLog("embedded.window.didMove origin=\(NSStringFromPoint(window.frame.origin))")
    }
#endif

    override var mouseDownCanMoveWindow: Bool { false }

    private func installTitlebarDragMonitor() {
        guard titlebarDragMonitor == nil else { return }
        titlebarDragMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self,
                  !self.didTearDown,
                  let window = self.window,
                  event.window === window,
                  event.clickCount == 1,
                  let contentView = window.contentView else { return event }

            if CmuxEmbeddedHeaderActionRegion.performActionIfHit(
                in: window,
                at: event.locationInWindow
            ) {
                return nil
            }

            guard !isMinimalModeTitlebarControlHit(
                window: window,
                locationInWindow: event.locationInWindow
            ) else { return event }

            let point = contentView.superview?.convert(event.locationInWindow, from: nil)
                ?? event.locationInWindow
            guard contentView.hitTest(point)?.identifier == WindowDragHandleView.viewIdentifier else {
                return event
            }

#if DEBUG
            cmuxDebugLog("embedded.titlebar.dragStart point=\(NSStringFromPoint(event.locationInWindow))")
#endif
            window.performDrag(with: event)
            return nil
        }
    }

    func closeCurrentPanel() {
        guard !didTearDown else { return }
        tabManager.closeCurrentPanelWithConfirmation()
    }

    func updateProjects(json: String) {
        guard !didTearDown,
              let data = json.data(using: .utf8),
              let snapshot = try? JSONDecoder().decode(ProjectsSnapshot.self, from: data) else { return }
        isSynchronizingProjects = true
        defer { isSynchronizingProjects = false }

        let desiredPaths = Set(snapshot.projects.map(\.path))
        for (path, id) in Array(projectWorkspaceIds) where !desiredPaths.contains(path) {
            if let workspace = tabManager.tabs.first(where: { $0.id == id }), tabManager.tabs.count > 1 {
                tabManager.closeWorkspace(workspace, recordHistory: false)
            }
            projectWorkspaceIds.removeValue(forKey: path)
            projectPathsByWorkspaceId.removeValue(forKey: id)
        }

        for project in snapshot.projects {
            if let id = projectWorkspaceIds[project.path],
               let workspace = tabManager.tabs.first(where: { $0.id == id }) {
                if workspace.customTitle != project.name || workspace.title != project.name {
                    tabManager.setCustomTitle(tabId: workspace.id, title: project.name, propagateToCloud: false)
                }
                continue
            }
            // Reuse the startup workspace before creating another terminal.
            let workspace: Workspace?
            if let unassigned = tabManager.tabs.first(where: { projectPathsByWorkspaceId[$0.id] == nil }) {
                workspace = unassigned
            } else {
                workspace = tabManager.addWorkspaceIfActive(
                    title: project.name,
                    workingDirectory: project.path,
                    inheritWorkingDirectory: false,
                    select: false,
                    eagerLoadTerminal: false,
                    autoWelcomeIfNeeded: false
                )
            }
            guard let workspace else { continue }
            tabManager.setCustomTitle(tabId: workspace.id, title: project.name, propagateToCloud: false)
            projectWorkspaceIds[project.path] = workspace.id
            projectPathsByWorkspaceId[workspace.id] = project.path
        }

        if let activePath = snapshot.activePath,
           let id = projectWorkspaceIds[activePath],
           let workspace = tabManager.tabs.first(where: { $0.id == id }),
           tabManager.selectedTabId != id {
            tabManager.selectWorkspace(workspace)
        }
    }

    func tearDown() {
        guard !didTearDown else { return }
        didTearDown = true
        subscriptions.removeAll()
        suspendWindowIntegration()
        tabManager.finalizeAllWorkspacesForWindowClose()
        hostingView.removeFromSuperview()
    }

    func suspendWindowIntegration() {
        guard let originalWindowState else { return }
        if let titlebarDragMonitor {
            NSEvent.removeMonitor(titlebarDragMonitor)
            self.titlebarDragMonitor = nil
        }
        let hostingWindow = window
        guard let hostingWindow else { return }
        NotificationCenter.default.removeObserver(self, name: NSWindow.didMoveNotification, object: hostingWindow)
        CmuxEmbeddedWindowDragPolicy.unmarkEmbedded(hostingWindow)
        TerminalWindowPortalRegistry.removePortal(for: hostingWindow)
        BrowserWindowPortalRegistry.removePortal(for: hostingWindow)
        needsPortalRebind = true
        let chrome = AppWindowChromeComposition()
        _ = chrome.glassEffect.remove(from: hostingWindow)
        chrome.nativeTitlebarBackdropCoordinator.syncNativeTitlebarBackdrop(
            in: hostingWindow,
            enabled: false,
            usesGlassStyle: false
        )
        chrome.nativeTitlebarBackdropCoordinator.removeNativeTitlebarBackdrop(in: hostingWindow)
        hostingWindow.identifier = originalWindowState.identifier
        hostingWindow.isRestorable = originalWindowState.isRestorable
        hostingWindow.isMovable = originalWindowState.isMovable
        hostingWindow.isMovableByWindowBackground = originalWindowState.isMovableByWindowBackground
        hostingWindow.titleVisibility = originalWindowState.titleVisibility
        hostingWindow.titlebarAppearsTransparent = originalWindowState.titlebarAppearsTransparent
        if originalWindowState.hasFullSizeContentView {
            hostingWindow.styleMask.insert(.fullSizeContentView)
        } else {
            hostingWindow.styleMask.remove(.fullSizeContentView)
        }
        hostingWindow.backgroundColor = originalWindowState.backgroundColor
        hostingWindow.isOpaque = originalWindowState.isOpaque
        self.originalWindowState = nil
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CmuxEmbeddedHostView does not support NSCoder initialization")
    }
}

@MainActor
private final class EmbeddedCmuxHostingView: NSHostingView<CmuxEmbeddedRootView> {
    override var mouseDownCanMoveWindow: Bool { false }
}
