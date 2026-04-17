import Foundation

@MainActor
final class WorkspaceEditorPresentationStore {
    private let presentationState: WorkspacePresentationState
    private let editorTabsForProject: @MainActor (String) -> [WorkspaceEditorTabState]

    init(
        presentationState: WorkspacePresentationState,
        editorTabsForProject: @escaping @MainActor (String) -> [WorkspaceEditorTabState]
    ) {
        self.presentationState = presentationState
        self.editorTabsForProject = editorTabsForProject
    }

    func defaultPresentation(tabs: [WorkspaceEditorTabState]) -> WorkspaceEditorPresentationState {
        guard !tabs.isEmpty else {
            return WorkspaceEditorPresentationState()
        }

        let defaultGroup = WorkspaceEditorGroupState(
            id: "workspace-editor-group:default",
            tabIDs: tabs.map(\.id),
            selectedTabID: tabs.last?.id
        )
        return WorkspaceEditorPresentationState(
            groups: [defaultGroup],
            activeGroupID: defaultGroup.id
        )
    }

    func normalizedPresentation(
        _ presentation: WorkspaceEditorPresentationState?,
        availableTabs: [WorkspaceEditorTabState]
    ) -> WorkspaceEditorPresentationState? {
        guard !availableTabs.isEmpty else {
            return nil
        }

        let availableTabIDs = availableTabs.map(\.id)
        let availableTabIDSet = Set(availableTabIDs)
        let sourcePresentation = presentation ?? defaultPresentation(tabs: availableTabs)

        var seen = Set<String>()
        var normalizedGroups: [WorkspaceEditorGroupState] = sourcePresentation.groups.map { group in
            var filteredTabIDs: [String] = []
            filteredTabIDs.reserveCapacity(group.tabIDs.count)
            for tabID in group.tabIDs where availableTabIDSet.contains(tabID) {
                guard seen.insert(tabID).inserted else {
                    continue
                }
                filteredTabIDs.append(tabID)
            }
            return WorkspaceEditorGroupState(
                id: group.id,
                tabIDs: filteredTabIDs,
                selectedTabID: group.selectedTabID
            )
        }

        if normalizedGroups.count > 2 {
            var mergedGroups = Array(normalizedGroups.prefix(2))
            for group in normalizedGroups.dropFirst(2) {
                for tabID in group.tabIDs where !mergedGroups[1].tabIDs.contains(tabID) {
                    mergedGroups[1].tabIDs.append(tabID)
                }
                if mergedGroups[1].selectedTabID == nil {
                    mergedGroups[1].selectedTabID = group.selectedTabID
                }
            }
            normalizedGroups = mergedGroups
        }

        if normalizedGroups.isEmpty {
            normalizedGroups = defaultPresentation(tabs: availableTabs).groups
        }

        let preferredActiveGroupID = sourcePresentation.activeGroupID
        let activeGroupIndex = normalizedGroups.firstIndex(where: { $0.id == preferredActiveGroupID })
            ?? normalizedGroups.firstIndex(where: { !$0.tabIDs.isEmpty })
            ?? 0

        let unassignedTabIDs = availableTabIDs.filter { !seen.contains($0) }
        if !unassignedTabIDs.isEmpty {
            normalizedGroups[activeGroupIndex].tabIDs.append(contentsOf: unassignedTabIDs)
        }

        for index in normalizedGroups.indices {
            let selectedTabID = normalizedGroups[index].selectedTabID
            if let selectedTabID,
               normalizedGroups[index].tabIDs.contains(selectedTabID) {
                continue
            }
            normalizedGroups[index].selectedTabID = normalizedGroups[index].tabIDs.last
        }

        return WorkspaceEditorPresentationState(
            groups: normalizedGroups,
            activeGroupID: normalizedGroups[activeGroupIndex].id,
            splitAxis: normalizedGroups.count > 1 ? (sourcePresentation.splitAxis ?? .horizontal) : nil,
            splitRatio: sourcePresentation.splitRatio
        )
    }

    func normalizedPresentation(
        _ presentation: WorkspaceEditorPresentationState?,
        in projectPath: String
    ) -> WorkspaceEditorPresentationState? {
        normalizedPresentation(
            presentation,
            availableTabs: editorTabsForProject(projectPath)
        )
    }

    func resolvedPresentation(for projectPath: String) -> WorkspaceEditorPresentationState? {
        normalizedPresentation(
            presentationState.editorPresentationByProjectPath[projectPath],
            in: projectPath
        )
    }

    func restorePresentation(for projectPath: String) -> WorkspaceEditorPresentationState? {
        let persistentTabs = editorTabsForProject(projectPath).filter { !$0.isPreview }
        return normalizedPresentation(
            presentationState.editorPresentationByProjectPath[projectPath],
            availableTabs: persistentTabs
        )
    }
}
