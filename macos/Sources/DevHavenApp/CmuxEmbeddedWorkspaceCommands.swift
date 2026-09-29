import SwiftUI

/// C ABI values implemented by cmux_embedded_host_view_perform_command.
enum CmuxEmbeddedWorkspaceCommand: Int32 {
    case newTerminalTab = 0
    case splitRight = 1
    case splitDown = 2
}

struct CmuxEmbeddedWorkspaceCommands: Commands {
    let isWorkspacePresented: Bool

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("新建终端标签") {
                CmuxEmbeddedWorkspaceActions.perform(.newTerminalTab)
            }
            .keyboardShortcut("t", modifiers: [.command])
            .disabled(!isWorkspacePresented)
        }

        CommandMenu("终端") {
            Button("向右分屏") {
                CmuxEmbeddedWorkspaceActions.perform(.splitRight)
            }
            .keyboardShortcut("d", modifiers: [.command])
            .disabled(!isWorkspacePresented)

            Button("向下分屏") {
                CmuxEmbeddedWorkspaceActions.perform(.splitDown)
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(!isWorkspacePresented)
        }
    }
}
