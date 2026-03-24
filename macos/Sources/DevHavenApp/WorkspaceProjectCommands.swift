import SwiftUI
import DevHavenCore

struct WorkspaceProjectCommands: Commands {
    let shortcut: AppMenuShortcut

    @FocusedValue(\.openWorkspaceProjectPickerAction) private var openWorkspaceProjectPickerAction

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("打开项目") {
                openWorkspaceProjectPickerAction?()
            }
            .keyboardShortcut(shortcut.keyEquivalent, modifiers: shortcut.eventModifiers)
            .disabled(openWorkspaceProjectPickerAction == nil)
        }
    }
}

private struct OpenWorkspaceProjectPickerActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var openWorkspaceProjectPickerAction: (() -> Void)? {
        get { self[OpenWorkspaceProjectPickerActionKey.self] }
        set { self[OpenWorkspaceProjectPickerActionKey.self] = newValue }
    }
}

private extension AppMenuShortcut {
    var keyEquivalent: KeyEquivalent {
        KeyEquivalent(Character(key.rawValue))
    }

    var eventModifiers: EventModifiers {
        var modifiers: EventModifiers = [.command]
        if usesShift {
            modifiers.insert(.shift)
        }
        if usesOption {
            modifiers.insert(.option)
        }
        if usesControl {
            modifiers.insert(.control)
        }
        return modifiers
    }
}
