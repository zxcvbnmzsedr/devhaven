import SwiftUI
import Observation
import DevHavenCore

struct WorkspaceProjectCommands: Commands {
    @ObservedObject var state: WorkspaceProjectCommandState
    let onOpenProjectPicker: () -> Void

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("打开项目", action: onOpenProjectPicker)
                .keyboardShortcut(state.shortcut.keyEquivalent, modifiers: state.shortcut.eventModifiers)
                .disabled(!state.isEnabled)
        }
    }
}

// Commands need an ObservableObject publisher to refresh an existing AppKit menu;
// reading the Core's @Observable model in a command builder leaves stale items.
@MainActor
final class WorkspaceProjectCommandState: ObservableObject {
    @Published private(set) var shortcut = AppMenuShortcut()
    @Published private(set) var isEnabled = false
    private let viewModel: NativeAppViewModel

    init(viewModel: NativeAppViewModel) {
        self.viewModel = viewModel
        refresh()
    }

    private func refresh() {
        let presentation = withObservationTracking {
            (
                shortcut: viewModel.snapshot.appState.settings.workspaceOpenProjectShortcut,
                isEnabled: viewModel.isWorkspacePresented
                    && !viewModel.isDashboardPresented
                    && !viewModel.isSettingsPresented
                    && !viewModel.isRecycleBinPresented
                    && !viewModel.isDetailPanelPresented
                    && viewModel.worktreeInteractionState == nil
                    && viewModel.errorMessage == nil
            )
        } onChange: { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        if shortcut != presentation.shortcut { shortcut = presentation.shortcut }
        if isEnabled != presentation.isEnabled { isEnabled = presentation.isEnabled }
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
