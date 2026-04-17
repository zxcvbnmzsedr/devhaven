import Foundation
import Observation

@MainActor
@Observable
final class WorkspacePresentationState {
    var sideToolWindowState: WorkspaceSideToolWindowState
    var bottomToolWindowState: WorkspaceBottomToolWindowState
    var focusedArea: WorkspaceFocusedArea
    var editorPresentationByProjectPath: [String: WorkspaceEditorPresentationState]
    var editorRuntimeSessionsByProjectPath: [String: [String: WorkspaceEditorRuntimeSessionState]]
    var diffTabsByProjectPath: [String: [WorkspaceDiffTabState]]
    var selectedPresentedTabsByProjectPath: [String: WorkspacePresentedTabSelection]

    init(
        sideToolWindowState: WorkspaceSideToolWindowState = WorkspaceSideToolWindowState(),
        bottomToolWindowState: WorkspaceBottomToolWindowState = WorkspaceBottomToolWindowState(),
        focusedArea: WorkspaceFocusedArea = .terminal,
        editorPresentationByProjectPath: [String: WorkspaceEditorPresentationState] = [:],
        editorRuntimeSessionsByProjectPath: [String: [String: WorkspaceEditorRuntimeSessionState]] = [:],
        diffTabsByProjectPath: [String: [WorkspaceDiffTabState]] = [:],
        selectedPresentedTabsByProjectPath: [String: WorkspacePresentedTabSelection] = [:]
    ) {
        self.sideToolWindowState = sideToolWindowState
        self.bottomToolWindowState = bottomToolWindowState
        self.focusedArea = focusedArea
        self.editorPresentationByProjectPath = editorPresentationByProjectPath
        self.editorRuntimeSessionsByProjectPath = editorRuntimeSessionsByProjectPath
        self.diffTabsByProjectPath = diffTabsByProjectPath
        self.selectedPresentedTabsByProjectPath = selectedPresentedTabsByProjectPath
    }
}
