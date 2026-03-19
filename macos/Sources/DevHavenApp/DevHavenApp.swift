import SwiftUI
import DevHavenCore

@main
struct DevHavenApp: App {
    @State private var viewModel = NativeAppViewModel()

    var body: some Scene {
        WindowGroup("DevHaven Native") {
            AppRootView(viewModel: viewModel)
                .frame(minWidth: 1280, minHeight: 820)
        }
        .defaultSize(width: 1480, height: 920)
        .commands {
            CommandMenu("DevHaven") {
                Button("刷新项目") {
                    viewModel.refresh()
                }
                .keyboardShortcut("r", modifiers: [.command])

                Divider()

                Button("设置") {
                    viewModel.revealSettings()
                }
                .keyboardShortcut(",", modifiers: [.command])

                Button("回收站") {
                    viewModel.revealRecycleBin()
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
            }
        }
    }
}
