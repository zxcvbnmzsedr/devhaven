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
    var body: some Commands {
        CommandGroup(after: .textEditing) {
            EmptyView()
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
