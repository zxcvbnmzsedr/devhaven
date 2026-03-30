import SwiftUI

struct WorkspaceEditorCommandRouter {
    var startSearchAction: () -> Void = {}
    var showReplaceAction: () -> Void = {}
    var navigateSearchNextAction: () -> Void = {}
    var navigateSearchPreviousAction: () -> Void = {}
    var useSelectionForSearchAction: () -> Void = {}
    var closeSearchAction: () -> Void = {}
    var goToLineAction: () -> Void = {}
    var saveAction: () -> Void = {}
    var reloadAction: () -> Void = {}
}

struct WorkspaceEditorCommands: Commands {
    @FocusedValue(\.workspaceEditorCommandRouter) private var editorCommandRouter
    @FocusedValue(\.workspaceEditorCommandsEnabled) private var editorCommandsEnabled

    private var isEnabled: Bool {
        editorCommandsEnabled ?? false
    }

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Button("跳转到行…") {
                editorCommandRouter?.goToLineAction()
            }
            .keyboardShortcut("l", modifiers: [.command])
            .disabled(!isEnabled)

            Divider()

            Button("保存") {
                editorCommandRouter?.saveAction()
            }
            .keyboardShortcut("s", modifiers: [.command])
            .disabled(!isEnabled)

            Button("重新载入") {
                editorCommandRouter?.reloadAction()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!isEnabled)
        }
    }
}

private struct WorkspaceEditorCommandRouterKey: FocusedValueKey {
    typealias Value = WorkspaceEditorCommandRouter
}

private struct WorkspaceEditorCommandsEnabledKey: FocusedValueKey {
    typealias Value = Bool
}

extension FocusedValues {
    var workspaceEditorCommandRouter: WorkspaceEditorCommandRouter? {
        get { self[WorkspaceEditorCommandRouterKey.self] }
        set { self[WorkspaceEditorCommandRouterKey.self] = newValue }
    }

    var workspaceEditorCommandsEnabled: Bool? {
        get { self[WorkspaceEditorCommandsEnabledKey.self] }
        set { self[WorkspaceEditorCommandsEnabledKey.self] = newValue }
    }
}
