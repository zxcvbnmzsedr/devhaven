import SwiftUI
import DevHavenCore

@main
struct DevHavenApp: App {
    @State private var viewModel = NativeAppViewModel()
    @StateObject private var updateController = DevHavenUpdateController()

    init() {
        _ = GhosttyAppRuntime.shared.runtime
    }

    var body: some Scene {
        WindowGroup("DevHaven Native") {
            AppRootView(viewModel: viewModel, updateController: updateController)
                .frame(minWidth: 1280, minHeight: 820)
        }
        .defaultSize(width: 1480, height: 920)
        .commands {
            CommandGroup(replacing: .newItem) {
            }

            CommandMenu("DevHaven") {
                Button(viewModel.isRefreshingProjectCatalog ? "正在刷新项目…" : "刷新项目") {
                    viewModel.refresh()
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(viewModel.isRefreshingProjectCatalog)

                Divider()

                Button("检查更新") {
                    updateController.checkForUpdates()
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])
                .disabled(!updateController.isSupported)

                Divider()

                Button("设置") {
                    viewModel.revealSettings()
                }
                .keyboardShortcut(",", modifiers: [.command])

                Button("回收站") {
                    viewModel.revealRecycleBin()
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])

                Divider()

                Button("向右分屏") {
                    _ = viewModel.activeWorkspaceController?.splitFocusedPane(direction: .right)
                }
                .keyboardShortcut("d", modifiers: [.command])
                .disabled(viewModel.activeWorkspaceController?.selectedPane == nil)
            }

            WorkspaceTerminalCommands()
        }
    }
}
