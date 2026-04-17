import Foundation

@MainActor
final class WorkspacePresentedTabCoordinator {
    private let presentationState: WorkspacePresentationState
    private let controllerForProject: @MainActor (String) -> GhosttyWorkspaceController?
    private let editorTabsForProject: @MainActor (String) -> [WorkspaceEditorTabState]
    private let activateEditorTab: @MainActor (String, String) -> Void
    private let selectProjectTreeNode: @MainActor (String?, String) -> Void
    private let showSideToolWindow: @MainActor (WorkspaceToolWindowKind) -> Void
    private let showBottomToolWindow: @MainActor (WorkspaceToolWindowKind) -> Void
    private let isBrowserPaneItem: @MainActor (String, String) -> Bool
    private let removeDiffViewModel: @MainActor (String) -> Void

    init(
        presentationState: WorkspacePresentationState,
        controllerForProject: @escaping @MainActor (String) -> GhosttyWorkspaceController?,
        editorTabsForProject: @escaping @MainActor (String) -> [WorkspaceEditorTabState],
        activateEditorTab: @escaping @MainActor (String, String) -> Void,
        selectProjectTreeNode: @escaping @MainActor (String?, String) -> Void,
        showSideToolWindow: @escaping @MainActor (WorkspaceToolWindowKind) -> Void,
        showBottomToolWindow: @escaping @MainActor (WorkspaceToolWindowKind) -> Void,
        isBrowserPaneItem: @escaping @MainActor (String, String) -> Bool,
        removeDiffViewModel: @escaping @MainActor (String) -> Void
    ) {
        self.presentationState = presentationState
        self.controllerForProject = controllerForProject
        self.editorTabsForProject = editorTabsForProject
        self.activateEditorTab = activateEditorTab
        self.selectProjectTreeNode = selectProjectTreeNode
        self.showSideToolWindow = showSideToolWindow
        self.showBottomToolWindow = showBottomToolWindow
        self.isBrowserPaneItem = isBrowserPaneItem
        self.removeDiffViewModel = removeDiffViewModel
    }

    func resolvedSelection(
        for projectPath: String,
        controller: GhosttyWorkspaceController? = nil
    ) -> WorkspacePresentedTabSelection? {
        let resolvedController = controller ?? controllerForProject(projectPath)
        let terminalTabID = resolvedController?.selectedTabId
            ?? resolvedController?.selectedTab?.id
        let editorTabs = editorTabsForProject(projectPath)
        let diffTabs = presentationState.diffTabsByProjectPath[projectPath] ?? []

        if let stored = presentationState.selectedPresentedTabsByProjectPath[projectPath] {
            switch stored {
            case let .terminal(tabID):
                if resolvedController?.tabs.contains(where: { $0.id == tabID }) == true {
                    return .terminal(tabID)
                }
            case let .editor(tabID):
                if editorTabs.contains(where: { $0.id == tabID }) {
                    return .editor(tabID)
                }
            case let .diff(tabID):
                if diffTabs.contains(where: { $0.id == tabID }) {
                    return .diff(tabID)
                }
            }
        }

        return terminalTabID.map(WorkspacePresentedTabSelection.terminal)
    }

    @discardableResult
    func select(_ selection: WorkspacePresentedTabSelection, in projectPath: String) -> Bool {
        switch selection {
        case let .terminal(tabID):
            guard controllerForProject(projectPath)?.tabs.contains(where: { $0.id == tabID }) == true else {
                return false
            }
            controllerForProject(projectPath)?.selectTab(tabID)
            presentationState.selectedPresentedTabsByProjectPath[projectPath] = .terminal(tabID)
            presentationState.focusedArea = .terminal
        case let .editor(tabID):
            guard let editorTab = editorTabsForProject(projectPath).first(where: { $0.id == tabID }) else {
                return false
            }
            activateEditorTab(tabID, projectPath)
            selectProjectTreeNode(editorTab.filePath, projectPath)
        case let .diff(tabID):
            guard (presentationState.diffTabsByProjectPath[projectPath] ?? []).contains(where: { $0.id == tabID }) else {
                return false
            }
            presentationState.selectedPresentedTabsByProjectPath[projectPath] = .diff(tabID)
            presentationState.focusedArea = .diffTab(tabID)
        }

        return true
    }

    @discardableResult
    func closeDiffTab(_ tabID: String, in projectPath: String) -> Bool {
        guard var tabs = presentationState.diffTabsByProjectPath[projectPath],
              let removedIndex = tabs.firstIndex(where: { $0.id == tabID })
        else {
            return false
        }

        let removedTab = tabs[removedIndex]
        let isClosingSelectedTab = resolvedSelection(for: projectPath) == .diff(tabID)
        tabs.remove(at: removedIndex)
        presentationState.diffTabsByProjectPath[projectPath] = tabs
        removeDiffViewModel(tabID)

        guard isClosingSelectedTab else {
            return true
        }

        if restoreOriginContext(for: removedTab, in: projectPath, remainingDiffTabs: tabs) {
            return true
        }

        if tabs.indices.contains(removedIndex) {
            presentationState.selectedPresentedTabsByProjectPath[projectPath] = .diff(tabs[removedIndex].id)
            presentationState.focusedArea = .diffTab(tabs[removedIndex].id)
        } else if let previous = tabs.last {
            presentationState.selectedPresentedTabsByProjectPath[projectPath] = .diff(previous.id)
            presentationState.focusedArea = .diffTab(previous.id)
        } else if let terminalTabID = controllerForProject(projectPath)?.selectedTabId
            ?? controllerForProject(projectPath)?.selectedTab?.id
        {
            presentationState.selectedPresentedTabsByProjectPath[projectPath] = .terminal(terminalTabID)
            presentationState.focusedArea = .terminal
        } else {
            presentationState.selectedPresentedTabsByProjectPath[projectPath] = nil
            presentationState.focusedArea = .terminal
        }

        return true
    }

    func defaultFocusedArea(for selection: WorkspacePresentedTabSelection) -> WorkspaceFocusedArea {
        switch selection {
        case .terminal:
            return .terminal
        case let .editor(tabID):
            return .editorTab(tabID)
        case let .diff(tabID):
            return .diffTab(tabID)
        }
    }

    private func restoreOriginContext(
        for tab: WorkspaceDiffTabState,
        in projectPath: String,
        remainingDiffTabs: [WorkspaceDiffTabState]
    ) -> Bool {
        guard let originContext = tab.originContext,
              let originSelection = validPresentedTabSelection(
                originContext.presentedTabSelection,
                in: projectPath,
                diffTabs: remainingDiffTabs
              )
        else {
            return false
        }

        select(originSelection, in: projectPath)
        _ = restoreFocusedArea(
            originContext.focusedArea,
            for: originSelection,
            in: projectPath,
            remainingDiffTabs: remainingDiffTabs
        )
        return true
    }

    private func validPresentedTabSelection(
        _ selection: WorkspacePresentedTabSelection?,
        in projectPath: String,
        diffTabs: [WorkspaceDiffTabState]
    ) -> WorkspacePresentedTabSelection? {
        guard let selection else {
            return nil
        }

        switch selection {
        case let .terminal(tabID):
            guard controllerForProject(projectPath)?.tabs.contains(where: { $0.id == tabID }) == true else {
                return nil
            }
            return .terminal(tabID)
        case let .editor(tabID):
            guard editorTabsForProject(projectPath).contains(where: { $0.id == tabID }) else {
                return nil
            }
            return .editor(tabID)
        case let .diff(tabID):
            guard diffTabs.contains(where: { $0.id == tabID }) else {
                return nil
            }
            return .diff(tabID)
        }
    }

    private func restoreFocusedArea(
        _ area: WorkspaceFocusedArea,
        for selection: WorkspacePresentedTabSelection,
        in projectPath: String,
        remainingDiffTabs: [WorkspaceDiffTabState]
    ) -> Bool {
        switch area {
        case .terminal:
            presentationState.focusedArea = .terminal
            return true
        case let .browserPaneItem(itemID):
            guard case .terminal = selection,
                  isBrowserPaneItem(itemID, projectPath)
            else {
                presentationState.focusedArea = defaultFocusedArea(for: selection)
                return false
            }
            presentationState.focusedArea = .browserPaneItem(itemID)
            return true
        case let .sideToolWindow(kind):
            showSideToolWindow(kind)
            return true
        case let .bottomToolWindow(kind):
            showBottomToolWindow(kind)
            return true
        case let .editorTab(tabID):
            guard validPresentedTabSelection(.editor(tabID), in: projectPath, diffTabs: remainingDiffTabs) != nil else {
                presentationState.focusedArea = defaultFocusedArea(for: selection)
                return false
            }
            presentationState.focusedArea = .editorTab(tabID)
            return true
        case let .diffTab(tabID):
            guard validPresentedTabSelection(.diff(tabID), in: projectPath, diffTabs: remainingDiffTabs) != nil else {
                presentationState.focusedArea = defaultFocusedArea(for: selection)
                return false
            }
            presentationState.focusedArea = .diffTab(tabID)
            return true
        }
    }
}
