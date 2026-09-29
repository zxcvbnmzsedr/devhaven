import SwiftUI
import AppKit
import Bonsplit
import CmuxUpdater
import CmuxAppKitSupportUI
import CmuxPanes
import Combine
import CmuxWorkspaces

/// Runs before DevHaven's SwiftUI App is initialized in a re-executed worker.
/// Keep the upstream isolated clipboard reader, deadlines and validation.
@_cdecl("cmux_embedded_run_paste_preparation_worker")
public func cmuxEmbeddedRunPastePreparationWorker() -> Int32 {
    TerminalPastePreparationWorker().run(arguments: CommandLine.arguments)
}

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
            autoWelcomeIfNeeded: false,
            tabDragTransferRegistry: tabDragTransferRegistry
        )
        tabManager.windowId = windowId
        tabManager.isEmbeddedInHost = true
        EmbeddedTerminalOwnerRegistry.managers.add(tabManager)
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

/// Stable command IDs shared with DevHaven's CmuxEmbeddedWorkspaceCommand.
/// Execute against this host's live TabManager, never the standalone app delegate.
@_cdecl("cmux_embedded_host_view_perform_command")
@MainActor
public func cmuxEmbeddedHostViewPerformCommand(_ hostPointer: UnsafeMutableRawPointer?, _ command: Int32) -> Bool {
    guard let hostPointer else { return false }
    return Unmanaged<CmuxEmbeddedHostView>.fromOpaque(hostPointer)
        .takeUnretainedValue()
        .performCommand(command)
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
    private var isProjectReconciliationScheduled = false
    private var hasRestoredProjectLayout = false
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
            .sink { [weak self] _ in
                self?.scheduleProjectReconciliation()
            }
            .store(in: &subscriptions)
        tabManager.workspaceGroupsPublisher
            .sink { [weak self] _ in self?.scheduleProjectReconciliation() }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                self?.saveProjectLayout()
                UserDefaults.standard.synchronize()
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

    private func scheduleProjectReconciliation() {
        guard !didTearDown, !isSynchronizingProjects, !isProjectReconciliationScheduled else { return }
        isProjectReconciliationScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isProjectReconciliationScheduled = false
            guard !self.didTearDown, !self.isSynchronizingProjects else { return }
            self.reconcileProjectsAfterWorkspaceMutation()
        }
    }

    private func reconcileProjectsAfterWorkspaceMutation() {
        defer { saveProjectLayout() }
        // tabsPublisher emits during willSet, including remove/insert steps of
        // a single drag reorder. Reconcile only the settled live list: a missing
        // ID in an intermediate publication is not a closed project. Group
        // creation also publishes its anchor before publishing group metadata.
        let liveIds = Set(tabManager.tabs.map(\.id))
        let closedProjects = projectWorkspaceIds.filter { !liveIds.contains($0.value) }
        for (path, id) in closedProjects {
            projectWorkspaceIds.removeValue(forKey: path)
            projectPathsByWorkspaceId.removeValue(forKey: id)
        }
        for path in closedProjects.keys {
            NotificationCenter.default.post(
                name: Notification.Name("DevHaven.CmuxEmbedded.ClosedProject"),
                object: path
            )
        }

        let unassigned = tabManager.tabs.filter {
            projectPathsByWorkspaceId[$0.id] == nil && !isGroupAnchor($0.id)
        }
        guard !unassigned.isEmpty else { return }
        for workspace in unassigned where tabManager.tabs.count > 1 {
            tabManager.closeWorkspace(workspace, recordHistory: false)
        }
        NotificationCenter.default.post(
            name: Notification.Name("DevHaven.CmuxEmbedded.OpenProjectPicker"),
            object: nil
        )
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

            // Let AppKit's traffic lights win even when embedded header or
            // drag views overlap them in the full-size content area.
            guard !isEmbeddedStandardWindowButtonHit(
                window: window,
                locationInWindow: event.locationInWindow
            ) else { return event }

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

    func performCommand(_ command: Int32) -> Bool {
        guard !didTearDown,
              originalWindowState != nil,
              let window, window.isKeyWindow,
              window.attachedSheet == nil,
              NSApp.modalWindow == nil,
              let workspace = tabManager.selectedWorkspace else { return false }

        switch command {
        case 0: // New terminal tab in the current project's focused pane.
            tabManager.newSurface()
            return true
        case 1, 2: // Split right / down.
            let direction: SplitDirection = command == 1 ? .right : .down
            if workspace.layoutMode == .canvas {
                return workspace.openNewCanvasPane(
                    type: .terminal,
                    focus: true,
                    direction: direction.canvasDirection
                ) != nil
            }
            return tabManager.createSplitOutcome(direction: direction).isAccepted
        default:
            return false
        }
    }

    func updateProjects(json: String) {
        guard !didTearDown,
              let data = json.data(using: .utf8),
              let snapshot = try? JSONDecoder().decode(ProjectsSnapshot.self, from: data) else { return }
        isSynchronizingProjects = true
        defer {
            isSynchronizingProjects = false
            saveProjectLayout()
        }

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
            if let unassigned = tabManager.tabs.first(where: {
                projectPathsByWorkspaceId[$0.id] == nil && !isGroupAnchor($0.id)
            }) {
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
        // Restore after active-project selection so its normal auto-expand
        // behavior cannot overwrite a saved collapsed group during startup.
        restoreProjectLayoutIfNeeded()
    }

    // Persist only sidebar organization. DevHaven remains the owner of which
    // projects reopen; cmux workspace UUIDs and terminal processes are transient.
    private struct ProjectLayout: Codable {
        var version = 1
        var groups: [Group]
        var projects: [Item]
        var order: [Row]

        struct Item: Codable {
            let path: String
            let isPinned: Bool
        }
        struct Group: Codable {
            let id: UUID
            let name: String
            let isCollapsed: Bool
            let isPinned: Bool
            let customColor: String?
            let iconSymbol: String?
            let externalID: String?
            let isEmpty: Bool
            let anchorProjectPath: String?
            let anchorDirectory: String?
            let projectPaths: [String]
        }
        enum Row: Codable {
            case project(String)
            case group(UUID)
        }
    }

    private static let projectLayoutKey = "DevHaven.CmuxEmbedded.ProjectLayout.v1"

    private func saveProjectLayout() {
        guard hasRestoredProjectLayout, !didTearDown else { return }
        let groups = tabManager.workspaceGroups.map { group in
            ProjectLayout.Group(
                id: group.id, name: group.name,
                isCollapsed: group.isCollapsed, isPinned: group.isPinned,
                customColor: group.customColor, iconSymbol: group.iconSymbol,
                externalID: group.externalID, isEmpty: group.isEmpty,
                anchorProjectPath: group.liveAnchorWorkspaceId.flatMap { projectPathsByWorkspaceId[$0] },
                anchorDirectory: group.liveAnchorWorkspaceId.flatMap { tabManager.workspacesById[$0]?.currentDirectory },
                projectPaths: tabManager.tabs.filter { $0.groupId == group.id }.compactMap { projectPathsByWorkspaceId[$0.id] }
            )
        }
        let groupsByAnchor = Dictionary(tabManager.workspaceGroups.map { ($0.anchorWorkspaceId, $0.id) }, uniquingKeysWith: { first, _ in first })
        // Header-only groups retain their slots through the ordered groups
        // array; cmux's normalizer merges those with these live top-level rows.
        let order = tabManager.tabs.compactMap { workspace -> ProjectLayout.Row? in
            if let groupId = groupsByAnchor[workspace.id] { return .group(groupId) }
            guard workspace.groupId == nil else { return nil }
            return projectPathsByWorkspaceId[workspace.id].map { .project($0) }
        }
        let projects = tabManager.tabs.compactMap { workspace -> ProjectLayout.Item? in
            guard let path = projectPathsByWorkspaceId[workspace.id] else { return nil }
            return .init(path: path, isPinned: workspace.isPinned)
        }
        let layout = ProjectLayout(groups: groups, projects: projects, order: order)
        guard let data = try? JSONEncoder().encode(layout) else { return }
        UserDefaults.standard.set(data, forKey: Self.projectLayoutKey)
    }

    private func restoreProjectLayoutIfNeeded() {
        guard !hasRestoredProjectLayout, !projectWorkspaceIds.isEmpty else { return }
        hasRestoredProjectLayout = true
        guard let data = UserDefaults.standard.data(forKey: Self.projectLayoutKey),
              let layout = try? JSONDecoder().decode(ProjectLayout.self, from: data),
              layout.version == 1,
              Set(layout.groups.map(\.id)).count == layout.groups.count else { return }

        var restoredGroups: [WorkspaceGroup] = []
        var membersByGroup: [UUID: [Workspace]] = [:]
        var claimedPaths = Set<String>()
        for saved in layout.groups {
            var members = saved.projectPaths.compactMap { path -> Workspace? in
                guard let id = projectWorkspaceIds[path],
                      let workspace = tabManager.workspacesById[id],
                      claimedPaths.insert(path).inserted else { return nil }
                return workspace
            }
            let anchor: Workspace?
            if let path = saved.anchorProjectPath,
               let id = projectWorkspaceIds[path],
               let member = members.first(where: { $0.id == id }) {
                anchor = member
            } else if saved.anchorProjectPath != nil, let first = members.first {
                anchor = first
            } else if saved.isEmpty && members.isEmpty {
                anchor = nil
            } else {
                anchor = tabManager.addWorkspaceIfActive(
                    title: saved.name, workingDirectory: saved.anchorDirectory,
                    inheritWorkingDirectory: false, select: false,
                    eagerLoadTerminal: false, autoWelcomeIfNeeded: false
                )
            }
            if let anchor {
                members.removeAll { $0.id == anchor.id }
                members.insert(anchor, at: 0)
                if projectPathsByWorkspaceId[anchor.id] == nil {
                    tabManager.setCustomTitle(tabId: anchor.id, title: saved.name, propagateToCloud: false)
                }
            }
            for member in members { member.groupId = saved.id }
            restoredGroups.append(WorkspaceGroup(
                id: saved.id, name: saved.name, isCollapsed: saved.isCollapsed,
                isPinned: saved.isPinned, anchor: anchor.map { .workspace($0.id) } ?? .empty(saved.id),
                customColor: saved.customColor, iconSymbol: saved.iconSymbol, externalID: saved.externalID,
                anchorWorkspaceProvenance: anchor.map { projectPathsByWorkspaceId[$0.id] == nil ? .generated : .user } ?? .unknown
            ))
            membersByGroup[saved.id] = members
        }
        tabManager.workspaceGroups = restoredGroups
        for project in layout.projects {
            if let id = projectWorkspaceIds[project.path] {
                tabManager.workspacesById[id]?.isPinned = project.isPinned
            }
        }
        var reordered: [Workspace] = []
        var topLevelIds: [UUID] = []
        var emitted = Set<UUID>()
        for row in layout.order {
            switch row {
            case let .project(path):
                guard let id = projectWorkspaceIds[path], let workspace = tabManager.workspacesById[id],
                      workspace.groupId == nil, emitted.insert(id).inserted else { continue }
                topLevelIds.append(id)
                reordered.append(workspace)
            case let .group(id):
                guard let group = restoredGroups.first(where: { $0.id == id }) else { continue }
                topLevelIds.append(group.anchorWorkspaceId)
                for member in membersByGroup[id] ?? [] where emitted.insert(member.id).inserted {
                    reordered.append(member)
                }
            }
        }
        reordered.append(contentsOf: tabManager.tabs.filter { emitted.insert($0.id).inserted })
        tabManager.tabs = reordered
        tabManager.workspaces.normalizeWorkspaceGroupContiguity(preservingTopLevelIds: topLevelIds)
    }

    private func isGroupAnchor(_ workspaceId: UUID) -> Bool {
        tabManager.workspaceGroups.contains { $0.liveAnchorWorkspaceId == workspaceId }
    }

    func tearDown() {
        guard !didTearDown else { return }
        saveProjectLayout()
        UserDefaults.standard.synchronize()
        didTearDown = true
        EmbeddedTerminalOwnerRegistry.managers.remove(tabManager)
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
