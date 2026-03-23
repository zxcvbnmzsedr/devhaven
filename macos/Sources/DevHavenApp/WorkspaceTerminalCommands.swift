import SwiftUI

struct WorkspaceTerminalCommands: Commands {
    @FocusedValue(\.startTerminalSearchAction) private var startTerminalSearchAction
    @FocusedValue(\.searchSelectionAction) private var searchSelectionAction
    @FocusedValue(\.navigateTerminalSearchNextAction) private var navigateTerminalSearchNextAction
    @FocusedValue(\.navigateTerminalSearchPreviousAction) private var navigateTerminalSearchPreviousAction
    @FocusedValue(\.endTerminalSearchAction) private var endTerminalSearchAction

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Button("查找…") {
                startTerminalSearchAction?()
            }
            .keyboardShortcut("f", modifiers: [.command])
            .disabled(startTerminalSearchAction == nil)

            Button("查找下一个") {
                navigateTerminalSearchNextAction?()
            }
            .keyboardShortcut("g", modifiers: [.command])
            .disabled(navigateTerminalSearchNextAction == nil)

            Button("查找上一个") {
                navigateTerminalSearchPreviousAction?()
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .disabled(navigateTerminalSearchPreviousAction == nil)

            Divider()

            Button("隐藏查找栏") {
                endTerminalSearchAction?()
            }
            .disabled(endTerminalSearchAction == nil)

            Divider()

            Button("使用所选内容查找") {
                searchSelectionAction?()
            }
            .keyboardShortcut("e", modifiers: [.command])
            .disabled(searchSelectionAction == nil)
        }
    }
}

private struct StartTerminalSearchActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct SearchSelectionActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct NavigateTerminalSearchNextActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct NavigateTerminalSearchPreviousActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct EndTerminalSearchActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var startTerminalSearchAction: (() -> Void)? {
        get { self[StartTerminalSearchActionKey.self] }
        set { self[StartTerminalSearchActionKey.self] = newValue }
    }

    var searchSelectionAction: (() -> Void)? {
        get { self[SearchSelectionActionKey.self] }
        set { self[SearchSelectionActionKey.self] = newValue }
    }

    var navigateTerminalSearchNextAction: (() -> Void)? {
        get { self[NavigateTerminalSearchNextActionKey.self] }
        set { self[NavigateTerminalSearchNextActionKey.self] = newValue }
    }

    var navigateTerminalSearchPreviousAction: (() -> Void)? {
        get { self[NavigateTerminalSearchPreviousActionKey.self] }
        set { self[NavigateTerminalSearchPreviousActionKey.self] = newValue }
    }

    var endTerminalSearchAction: (() -> Void)? {
        get { self[EndTerminalSearchActionKey.self] }
        set { self[EndTerminalSearchActionKey.self] = newValue }
    }
}
