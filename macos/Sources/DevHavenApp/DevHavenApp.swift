import AppKit
import SwiftUI
import DevHavenCore

@MainActor
final class DevHavenAppDelegate: NSObject, NSApplicationDelegate {
    private let mainWindowRestorer = MainWindowRestorer()

    func applicationDidBecomeActive(_ notification: Notification) {
        _ = mainWindowRestorer.showMainWindowIfNeeded(
            application: AppKitMainWindowRestoringApplicationProxy(application: NSApp)
        )
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if flag {
            return true
        }
        return mainWindowRestorer.showMainWindowIfNeeded(
            application: AppKitMainWindowRestoringApplicationProxy(application: sender)
        ) ? false : true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct DevHavenApp: App {
    @NSApplicationDelegateAdaptor(DevHavenAppDelegate.self) private var appDelegate
    @State private var viewModel = NativeAppViewModel()
    @StateObject private var updateController = DevHavenUpdateController()
    @StateObject private var quitGuard = AppQuitGuard()

    init() {
        _ = GhosttyAppRuntime.shared.runtime
    }

    var body: some Scene {
        WindowGroup("DevHaven Native") {
            AppRootView(
                viewModel: viewModel,
                updateController: updateController,
                quitGuard: quitGuard
            )
                .frame(minWidth: 1280, minHeight: 820)
        }
        .defaultSize(width: 1480, height: 920)
        .commands {
            CommandGroup(replacing: .newItem) {
            }

            CommandGroup(replacing: .appTermination) {
                Button("退出 DevHaven") {
                    quitGuard.requestQuit()
                }
                .keyboardShortcut("q", modifiers: [.command])
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

            WorkspaceSearchCommands()
            WorkspaceEditorCommands()
            WorkspaceProjectCommands(
                shortcut: viewModel.snapshot.appState.settings.workspaceOpenProjectShortcut
            )
        }
    }
}

@MainActor
protocol MainWindowRestoringApplication {
    var windows: [any MainWindowRestoringWindow] { get }
    func activateIgnoringOtherApps()
}

@MainActor
protocol MainWindowRestoringWindow {
    var identifier: String? { get }
    var isVisible: Bool { get }
    var isMiniaturized: Bool { get }
    func deminiaturize()
    func makeKeyAndOrderFront()
}

@MainActor
final class MainWindowRestorer {
    @discardableResult
    func showMainWindowIfNeeded(application: any MainWindowRestoringApplication) -> Bool {
        guard !application.windows.contains(where: \.isVisible) else {
            return false
        }
        guard let window = mainWindow(from: application.windows) else {
            return false
        }
        if window.isMiniaturized {
            window.deminiaturize()
        }
        application.activateIgnoringOtherApps()
        window.makeKeyAndOrderFront()
        return true
    }

    private func mainWindow(from windows: [any MainWindowRestoringWindow]) -> (any MainWindowRestoringWindow)? {
        if let mainWindow = windows.first(where: { $0.identifier == "main" }) {
            return mainWindow
        }
        if let primaryWindow = windows.first(where: { $0.identifier != "settings" }) {
            return primaryWindow
        }
        return windows.first
    }
}

@MainActor
struct AppKitMainWindowRestoringApplicationProxy: MainWindowRestoringApplication {
    let application: NSApplication

    var windows: [any MainWindowRestoringWindow] {
        application.windows.map(AppKitMainWindowRestoringWindowProxy.init(window:))
    }

    func activateIgnoringOtherApps() {
        application.activate(ignoringOtherApps: true)
    }
}

@MainActor
struct AppKitMainWindowRestoringWindowProxy: MainWindowRestoringWindow {
    let window: NSWindow

    var identifier: String? {
        window.identifier?.rawValue
    }

    var isVisible: Bool {
        window.isVisible
    }

    var isMiniaturized: Bool {
        window.isMiniaturized
    }

    func deminiaturize() {
        window.deminiaturize(nil)
    }

    func makeKeyAndOrderFront() {
        window.makeKeyAndOrderFront(nil)
    }
}
