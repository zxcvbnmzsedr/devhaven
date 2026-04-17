import Foundation

@MainActor
final class WorkspaceEditorCloseCoordinator {
    struct BeginCloseResult {
        var forceCloseTabIDs: [String]
        var request: WorkspaceEditorCloseRequest?
    }

    struct ConfirmCloseResult {
        var projectPath: String
        var tabID: String
        var remainingTabIDs: [String]
    }

    enum PostCloseSelection: Equatable {
        case editor(String)
        case diff(String)
        case terminal(String)
        case none
    }

    private struct BatchCloseState {
        var projectPath: String
        var remainingTabIDs: [String]
    }

    private var batchCloseState: BatchCloseState?

    func beginClosing(
        _ tabIDs: [String],
        in resolvedProjectPath: String,
        displayProjectPath: String,
        tabs: [WorkspaceEditorTabState]
    ) -> BeginCloseResult {
        batchCloseState = nil

        var forceCloseTabIDs: [String] = []
        for (index, tabID) in tabIDs.enumerated() {
            guard let tab = tabs.first(where: { $0.id == tabID }) else {
                continue
            }

            guard !tab.isDirty else {
                let remainingTabIDs = Array(tabIDs.suffix(from: index + 1))
                batchCloseState = remainingTabIDs.isEmpty
                    ? nil
                    : BatchCloseState(
                        projectPath: resolvedProjectPath,
                        remainingTabIDs: remainingTabIDs
                    )
                return BeginCloseResult(
                    forceCloseTabIDs: forceCloseTabIDs,
                    request: WorkspaceEditorCloseRequest(
                        projectPath: displayProjectPath,
                        tabID: tabID,
                        title: tab.title,
                        filePath: tab.filePath,
                        isDirty: tab.isDirty,
                        externalChangeState: tab.externalChangeState
                    )
                )
            }

            forceCloseTabIDs.append(tabID)
        }

        return BeginCloseResult(forceCloseTabIDs: forceCloseTabIDs, request: nil)
    }

    func confirmCloseRequest(_ request: WorkspaceEditorCloseRequest) -> ConfirmCloseResult {
        let currentBatch = batchCloseState
        batchCloseState = nil
        return ConfirmCloseResult(
            projectPath: currentBatch?.projectPath ?? request.projectPath,
            tabID: request.tabID,
            remainingTabIDs: currentBatch?.remainingTabIDs ?? []
        )
    }

    func dismissCloseRequest() {
        batchCloseState = nil
    }

    func reset() {
        batchCloseState = nil
    }

    func postCloseSelection(
        preferredEditorTabID: String?,
        diffTabs: [WorkspaceDiffTabState],
        terminalTabID: String?
    ) -> PostCloseSelection {
        if let preferredEditorTabID {
            return .editor(preferredEditorTabID)
        }
        if let diffTabID = diffTabs.last?.id {
            return .diff(diffTabID)
        }
        if let terminalTabID {
            return .terminal(terminalTabID)
        }
        return .none
    }
}
