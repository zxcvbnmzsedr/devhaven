import Foundation

@MainActor
final class WorkspacePresentedTabSnapshotBuilder {
    func snapshot(
        controller: GhosttyWorkspaceController?,
        editorTabs: [WorkspaceEditorTabState],
        diffTabs: [WorkspaceDiffTabState],
        selection: WorkspacePresentedTabSelection?
    ) -> NativeAppViewModel.WorkspacePresentedTabSnapshot {
        let terminalTabs = controller?.tabs.map { tab in
            WorkspacePresentedTabItem(
                id: tab.id,
                title: tab.title,
                selection: .terminal(tab.id),
                isSelected: selection == .terminal(tab.id)
            )
        } ?? []
        let editorItems = editorTabs.map { tab in
            WorkspacePresentedTabItem(
                id: tab.id,
                title: tab.isDirty ? "● \(tab.title)" : tab.title,
                selection: .editor(tab.id),
                isSelected: selection == .editor(tab.id),
                isPinned: tab.isPinned,
                isPreview: tab.isPreview
            )
        }
        let diffItems = diffTabs.map { tab in
            WorkspacePresentedTabItem(
                id: tab.id,
                title: tab.title,
                selection: .diff(tab.id),
                isSelected: selection == .diff(tab.id)
            )
        }
        return NativeAppViewModel.WorkspacePresentedTabSnapshot(
            items: terminalTabs + editorItems + diffItems,
            selection: selection
        )
    }
}
