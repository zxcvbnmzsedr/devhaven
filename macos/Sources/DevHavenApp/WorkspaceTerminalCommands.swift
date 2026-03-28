import SwiftUI

@MainActor
final class WorkspaceTerminalCommandRouter {
    var resolveActiveModel: (() -> GhosttySurfaceHostModel?)?

    lazy var startSearchAction: () -> Void = { [weak self] in
        self?.resolveActiveModel?()?.startSearch()
    }

    lazy var searchSelectionAction: () -> Void = { [weak self] in
        self?.resolveActiveModel?()?.searchSelection()
    }

    lazy var navigateSearchNextAction: () -> Void = { [weak self] in
        self?.resolveActiveModel?()?.navigateSearchNext()
    }

    lazy var navigateSearchPreviousAction: () -> Void = { [weak self] in
        self?.resolveActiveModel?()?.navigateSearchPrevious()
    }

    lazy var endSearchAction: () -> Void = { [weak self] in
        self?.resolveActiveModel?()?.endSearch()
    }
}

struct WorkspaceTerminalCommands: Commands {
    @FocusedValue(\.workspaceTerminalCommandRouter) private var terminalCommandRouter
    @FocusedValue(\.workspaceTerminalSearchActionsEnabled) private var terminalSearchActionsEnabled

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Button("查找…") {
                terminalCommandRouter?.startSearchAction()
            }
            .keyboardShortcut("f", modifiers: [.command])
            .disabled(!(terminalSearchActionsEnabled ?? false))

            Button("查找下一个") {
                terminalCommandRouter?.navigateSearchNextAction()
            }
            .keyboardShortcut("g", modifiers: [.command])
            .disabled(!(terminalSearchActionsEnabled ?? false))

            Button("查找上一个") {
                terminalCommandRouter?.navigateSearchPreviousAction()
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .disabled(!(terminalSearchActionsEnabled ?? false))

            Divider()

            Button("隐藏查找栏") {
                terminalCommandRouter?.endSearchAction()
            }
            .disabled(!(terminalSearchActionsEnabled ?? false))

            Divider()

            Button("使用所选内容查找") {
                terminalCommandRouter?.searchSelectionAction()
            }
            .keyboardShortcut("e", modifiers: [.command])
            .disabled(!(terminalSearchActionsEnabled ?? false))
        }
    }
}

private struct WorkspaceTerminalCommandRouterKey: FocusedValueKey {
    typealias Value = WorkspaceTerminalCommandRouter
}

private struct WorkspaceTerminalSearchActionsEnabledKey: FocusedValueKey {
    typealias Value = Bool
}

extension FocusedValues {
    var workspaceTerminalCommandRouter: WorkspaceTerminalCommandRouter? {
        get { self[WorkspaceTerminalCommandRouterKey.self] }
        set { self[WorkspaceTerminalCommandRouterKey.self] = newValue }
    }

    var workspaceTerminalSearchActionsEnabled: Bool? {
        get { self[WorkspaceTerminalSearchActionsEnabledKey.self] }
        set { self[WorkspaceTerminalSearchActionsEnabledKey.self] = newValue }
    }
}
