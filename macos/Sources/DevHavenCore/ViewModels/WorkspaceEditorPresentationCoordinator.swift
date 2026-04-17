import Foundation

@MainActor
final class WorkspaceEditorPresentationCoordinator {
    struct MutationResult {
        var didMutate: Bool
        var selectedTabID: String?
    }

    private let presentationState: WorkspacePresentationState
    private let editorTabsForProject: @MainActor (String) -> [WorkspaceEditorTabState]
    private let presentationStore: WorkspaceEditorPresentationStore
    private let selectProjectTreeNode: @MainActor (String?, String) -> Void

    init(
        presentationState: WorkspacePresentationState,
        editorTabsForProject: @escaping @MainActor (String) -> [WorkspaceEditorTabState],
        presentationStore: WorkspaceEditorPresentationStore,
        selectProjectTreeNode: @escaping @MainActor (String?, String) -> Void
    ) {
        self.presentationState = presentationState
        self.editorTabsForProject = editorTabsForProject
        self.presentationStore = presentationStore
        self.selectProjectTreeNode = selectProjectTreeNode
    }

    func activateTab(_ tabID: String, in projectPath: String) -> Bool {
        let availableTabs = editorTabsForProject(projectPath)
        guard let editorTab = availableTabs.first(where: { $0.id == tabID }) else {
            return false
        }

        var presentation = presentationStore.resolvedPresentation(for: projectPath)
            ?? presentationStore.defaultPresentation(tabs: availableTabs)
        if let groupIndex = presentation.groups.firstIndex(where: { $0.tabIDs.contains(tabID) }) {
            presentation.activeGroupID = presentation.groups[groupIndex].id
            presentation.groups[groupIndex].selectedTabID = tabID
        } else {
            presentation = presentationStore.defaultPresentation(tabs: availableTabs)
            if let groupIndex = presentation.groups.firstIndex(where: { $0.tabIDs.contains(tabID) }) {
                presentation.activeGroupID = presentation.groups[groupIndex].id
                presentation.groups[groupIndex].selectedTabID = tabID
            }
        }

        presentationState.editorPresentationByProjectPath[projectPath] = presentationStore.normalizedPresentation(
            presentation,
            in: projectPath
        )
        presentationState.selectedPresentedTabsByProjectPath[projectPath] = .editor(tabID)
        presentationState.focusedArea = .editorTab(tabID)
        selectProjectTreeNode(editorTab.filePath, projectPath)
        return true
    }

    func assignTabToActiveGroup(_ tabID: String, in projectPath: String) {
        let availableTabs = editorTabsForProject(projectPath)
        guard availableTabs.contains(where: { $0.id == tabID }) else {
            return
        }

        var presentation = presentationStore.resolvedPresentation(for: projectPath)
            ?? presentationStore.defaultPresentation(tabs: availableTabs)
        if presentation.groups.isEmpty {
            presentation = presentationStore.defaultPresentation(tabs: availableTabs)
        }

        let activeGroupIndex = presentation.groups.firstIndex(where: { $0.id == presentation.activeGroupID }) ?? 0
        for index in presentation.groups.indices {
            presentation.groups[index].tabIDs.removeAll(where: { $0 == tabID })
            if presentation.groups[index].selectedTabID == tabID {
                presentation.groups[index].selectedTabID = presentation.groups[index].tabIDs.last
            }
        }

        presentation.groups[activeGroupIndex].tabIDs.append(tabID)
        presentation.groups[activeGroupIndex].selectedTabID = tabID
        presentation.activeGroupID = presentation.groups[activeGroupIndex].id
        presentationState.editorPresentationByProjectPath[projectPath] = presentationStore.normalizedPresentation(
            presentation,
            in: projectPath
        )
    }

    func splitActiveGroup(
        axis: WorkspaceSplitAxis,
        in projectPath: String
    ) -> MutationResult {
        let availableTabs = editorTabsForProject(projectPath)
        guard !availableTabs.isEmpty else {
            return MutationResult(didMutate: false, selectedTabID: nil)
        }

        var presentation = presentationStore.resolvedPresentation(for: projectPath)
            ?? WorkspaceEditorPresentationState()
        if presentation.groups.isEmpty {
            presentation = presentationStore.defaultPresentation(tabs: availableTabs)
        }

        let activeGroupID = presentation.activeGroupID ?? presentation.groups.first?.id
        guard let activeGroupID,
              let activeGroupIndex = presentation.groups.firstIndex(where: { $0.id == activeGroupID })
        else {
            return MutationResult(didMutate: false, selectedTabID: nil)
        }

        if presentation.groups.count == 1 {
            let newGroup = WorkspaceEditorGroupState(
                id: "workspace-editor-group:\(UUID().uuidString.lowercased())"
            )
            presentation.groups.insert(newGroup, at: activeGroupIndex + 1)
            presentation.activeGroupID = newGroup.id
            presentation.splitAxis = axis
            presentation.splitRatio = WorkspaceEditorPresentationState.defaultSplitRatio
        } else {
            presentation.activeGroupID = presentation.groups[min(activeGroupIndex + 1, presentation.groups.count - 1)].id
            presentation.splitAxis = axis
        }

        let normalized = presentationStore.normalizedPresentation(presentation, in: projectPath)
        presentationState.editorPresentationByProjectPath[projectPath] = normalized
        let selectedTabID = normalized?.groups.first(where: { $0.id == normalized?.activeGroupID })?.selectedTabID
        return MutationResult(didMutate: true, selectedTabID: selectedTabID)
    }

    func selectGroup(_ groupID: String, in projectPath: String) -> MutationResult {
        guard var presentation = presentationStore.resolvedPresentation(for: projectPath),
              let groupIndex = presentation.groups.firstIndex(where: { $0.id == groupID })
        else {
            return MutationResult(didMutate: false, selectedTabID: nil)
        }

        presentation.activeGroupID = presentation.groups[groupIndex].id
        let normalized = presentationStore.normalizedPresentation(presentation, in: projectPath)
        presentationState.editorPresentationByProjectPath[projectPath] = normalized
        return MutationResult(
            didMutate: true,
            selectedTabID: normalized?.groups.first(where: { $0.id == groupID })?.selectedTabID
        )
    }

    func moveTab(
        _ tabID: String,
        toGroup groupID: String,
        in projectPath: String
    ) -> Bool {
        guard editorTabsForProject(projectPath).contains(where: { $0.id == tabID }),
              var presentation = presentationStore.resolvedPresentation(for: projectPath),
              let targetGroupIndex = presentation.groups.firstIndex(where: { $0.id == groupID })
        else {
            return false
        }

        for index in presentation.groups.indices {
            presentation.groups[index].tabIDs.removeAll(where: { $0 == tabID })
            if presentation.groups[index].selectedTabID == tabID {
                presentation.groups[index].selectedTabID = presentation.groups[index].tabIDs.last
            }
        }

        presentation.groups[targetGroupIndex].tabIDs.append(tabID)
        presentation.groups[targetGroupIndex].selectedTabID = tabID
        presentation.activeGroupID = presentation.groups[targetGroupIndex].id
        presentationState.editorPresentationByProjectPath[projectPath] = presentationStore.normalizedPresentation(
            presentation,
            in: projectPath
        )
        return true
    }

    func closeGroup(_ groupID: String, in projectPath: String) -> MutationResult {
        guard var presentation = presentationStore.resolvedPresentation(for: projectPath),
              presentation.groups.count > 1,
              let closingGroupIndex = presentation.groups.firstIndex(where: { $0.id == groupID })
        else {
            return MutationResult(didMutate: false, selectedTabID: nil)
        }

        let fallbackGroupIndex = closingGroupIndex == 0 ? 1 : 0
        let movedTabIDs = presentation.groups[closingGroupIndex].tabIDs
        for tabID in movedTabIDs where !presentation.groups[fallbackGroupIndex].tabIDs.contains(tabID) {
            presentation.groups[fallbackGroupIndex].tabIDs.append(tabID)
        }
        if presentation.groups[fallbackGroupIndex].selectedTabID == nil {
            presentation.groups[fallbackGroupIndex].selectedTabID = presentation.groups[closingGroupIndex].selectedTabID
                ?? movedTabIDs.last
        }
        presentation.groups.remove(at: closingGroupIndex)
        presentation.activeGroupID = presentation.groups.indices.contains(fallbackGroupIndex)
            ? presentation.groups[fallbackGroupIndex].id
            : presentation.groups.last?.id
        presentation.splitAxis = presentation.groups.count > 1 ? presentation.splitAxis : nil

        let normalized = presentationStore.normalizedPresentation(presentation, in: projectPath)
        presentationState.editorPresentationByProjectPath[projectPath] = normalized

        if let selectedEditorTabID = currentSelectedEditorTabID(in: projectPath),
           editorTabsForProject(projectPath).contains(where: { $0.id == selectedEditorTabID }) {
            return MutationResult(didMutate: true, selectedTabID: selectedEditorTabID)
        }
        return MutationResult(
            didMutate: true,
            selectedTabID: normalized?.groups.last?.selectedTabID ?? normalized?.groups.last?.tabIDs.last
        )
    }

    func updateSplitRatio(
        _ ratio: Double,
        in projectPath: String
    ) -> Bool {
        guard var presentation = presentationStore.resolvedPresentation(for: projectPath),
              presentation.groups.count > 1
        else {
            return false
        }

        presentation.splitRatio = min(max(ratio, 0.15), 0.85)
        presentationState.editorPresentationByProjectPath[projectPath] = presentation
        return true
    }

    func removeTab(
        _ tabID: String,
        from presentation: WorkspaceEditorPresentationState?,
        in projectPath: String
    ) -> WorkspaceEditorPresentationState? {
        guard var presentation else {
            return presentationStore.normalizedPresentation(nil, in: projectPath)
        }

        for index in presentation.groups.indices {
            presentation.groups[index].tabIDs.removeAll(where: { $0 == tabID })
            if presentation.groups[index].selectedTabID == tabID {
                presentation.groups[index].selectedTabID = presentation.groups[index].tabIDs.last
            }
        }
        return presentationStore.normalizedPresentation(presentation, in: projectPath)
    }

    func preferredTabAfterClosing(
        removedIndex: Int,
        in projectPath: String,
        remainingTabs: [WorkspaceEditorTabState]
    ) -> String? {
        if let presentation = presentationStore.resolvedPresentation(for: projectPath),
           let activeGroup = presentation.groups.first(where: { $0.id == presentation.activeGroupID }) {
            if let selectedTabID = activeGroup.selectedTabID {
                return selectedTabID
            }
            if let lastTabID = activeGroup.tabIDs.last {
                return lastTabID
            }
        }

        if remainingTabs.indices.contains(removedIndex) {
            return remainingTabs[removedIndex].id
        }
        return remainingTabs.last?.id
    }

    private func currentSelectedEditorTabID(in projectPath: String) -> String? {
        guard case let .editor(tabID)? = presentationState.selectedPresentedTabsByProjectPath[projectPath] else {
            return nil
        }
        return tabID
    }
}
