import AppKit
import DevHavenCore

@MainActor
enum DetailPanelCloseAction {
    static func perform(for viewModel: NativeAppViewModel, window: NSWindow? = NSApp.keyWindow ?? NSApp.mainWindow) {
        if viewModel.isDetailPanelPresented {
            window?.makeFirstResponder(nil)
        }
        viewModel.closeDetailPanel()
    }
}
