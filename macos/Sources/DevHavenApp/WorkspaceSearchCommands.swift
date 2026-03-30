import SwiftUI

enum WorkspaceSearchCommandTarget: Equatable {
    case none
    case editor
    case terminal
}

func workspaceSearchCommandTarget(
    editorEnabled: Bool,
    terminalEnabled: Bool
) -> WorkspaceSearchCommandTarget {
    if editorEnabled {
        return .editor
    }
    if terminalEnabled {
        return .terminal
    }
    return .none
}

struct WorkspaceSearchCommands: Commands {
    @FocusedValue(\.workspaceEditorCommandRouter) private var editorCommandRouter
    @FocusedValue(\.workspaceEditorCommandsEnabled) private var editorCommandsEnabled
    @FocusedValue(\.workspaceTerminalCommandRouter) private var terminalCommandRouter
    @FocusedValue(\.workspaceTerminalSearchActionsEnabled) private var terminalSearchActionsEnabled

    private var activeTarget: WorkspaceSearchCommandTarget {
        workspaceSearchCommandTarget(
            editorEnabled: editorCommandsEnabled ?? false,
            terminalEnabled: terminalSearchActionsEnabled ?? false
        )
    }

    private var isEditorEnabled: Bool {
        editorCommandsEnabled ?? false
    }

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Button("查找…") {
                switch activeTarget {
                case .editor:
                    editorCommandRouter?.startSearchAction()
                case .terminal:
                    terminalCommandRouter?.startSearchAction()
                case .none:
                    break
                }
            }
            .keyboardShortcut("f", modifiers: [.command])
            .disabled(activeTarget == .none)

            Button("替换…") {
                editorCommandRouter?.showReplaceAction()
            }
            .keyboardShortcut("f", modifiers: [.command, .option])
            .disabled(!isEditorEnabled)

            Button("查找下一个") {
                switch activeTarget {
                case .editor:
                    editorCommandRouter?.navigateSearchNextAction()
                case .terminal:
                    terminalCommandRouter?.navigateSearchNextAction()
                case .none:
                    break
                }
            }
            .keyboardShortcut("g", modifiers: [.command])
            .disabled(activeTarget == .none)

            Button("查找上一个") {
                switch activeTarget {
                case .editor:
                    editorCommandRouter?.navigateSearchPreviousAction()
                case .terminal:
                    terminalCommandRouter?.navigateSearchPreviousAction()
                case .none:
                    break
                }
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .disabled(activeTarget == .none)

            Divider()

            Button("使用所选内容查找") {
                switch activeTarget {
                case .editor:
                    editorCommandRouter?.useSelectionForSearchAction()
                case .terminal:
                    terminalCommandRouter?.searchSelectionAction()
                case .none:
                    break
                }
            }
            .keyboardShortcut("e", modifiers: [.command])
            .disabled(activeTarget == .none)

            Divider()

            Button("隐藏查找栏") {
                switch activeTarget {
                case .editor:
                    editorCommandRouter?.closeSearchAction()
                case .terminal:
                    terminalCommandRouter?.endSearchAction()
                case .none:
                    break
                }
            }
            .keyboardShortcut(.escape, modifiers: [])
            .disabled(activeTarget == .none)
        }
    }
}
