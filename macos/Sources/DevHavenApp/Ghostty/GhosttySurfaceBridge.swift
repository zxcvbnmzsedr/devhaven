import AppKit
import Foundation
import GhosttyKit

final class GhosttySurfaceBridge {
    let state = GhosttySurfaceState()

    weak var surfaceView: GhosttyTerminalSurfaceView?
    var surface: ghostty_surface_t?

    var onTitleChange: ((String) -> Void)?
    var onWorkingDirectoryChange: ((String) -> Void)?
    var onRendererHealthChange: ((Bool) -> Void)?
    var onAppearanceChange: ((GhosttySurfaceAppearance) -> Void)?
    var onCloseRequest: ((Bool) -> Void)?

    @MainActor
    func handleAction(target: ghostty_target_s, action: ghostty_action_s) -> Bool {
        _ = target

        switch action.tag {
        case GHOSTTY_ACTION_SET_TITLE:
            guard let title = string(from: action.action.set_title.title) else {
                return true
            }
            state.title = title
            onTitleChange?(title)
            return true

        case GHOSTTY_ACTION_PWD:
            guard let path = string(from: action.action.pwd.pwd) else {
                return true
            }
            state.pwd = path
            onWorkingDirectoryChange?(path)
            return true

        case GHOSTTY_ACTION_CELL_SIZE:
            let size = NSSize(
                width: Double(action.action.cell_size.width),
                height: Double(action.action.cell_size.height)
            )
            surfaceView?.updateCellSize(size)
            return true

        case GHOSTTY_ACTION_RENDERER_HEALTH:
            let healthy = action.action.renderer_health == GHOSTTY_RENDERER_HEALTH_OK
            state.rendererHealthy = healthy
            onRendererHealthChange?(healthy)
            return true

        case GHOSTTY_ACTION_CONFIG_CHANGE:
            let appearance = GhosttySurfaceAppearance(config: action.action.config_change.config)
            state.appearance = appearance
            onAppearanceChange?(appearance)
            return true

        case GHOSTTY_ACTION_COLOR_CHANGE:
            let appearance = GhosttySurfaceAppearance(
                backgroundColorChange: action.action.color_change,
                fallback: state.appearance
            )
            state.appearance = appearance
            onAppearanceChange?(appearance)
            return true

        case GHOSTTY_ACTION_OPEN_URL:
            return openURL(action.action.open_url)

        default:
            return false
        }
    }

    @MainActor
    func closeSurface(processAlive: Bool) {
        onCloseRequest?(processAlive)
    }

    private func string(from cString: UnsafePointer<CChar>?) -> String? {
        guard let cString else {
            return nil
        }
        return String(cString: cString)
    }

    private func openURL(_ action: ghostty_action_open_url_s) -> Bool {
        let length = Int(action.len)
        guard let pointer = action.url, length > 0 else {
            return false
        }
        let data = Data(bytes: pointer, count: length)
        guard let string = String(data: data, encoding: .utf8), !string.isEmpty else {
            return false
        }

        let url = URL(string: string) ?? URL(fileURLWithPath: string)
        NSWorkspace.shared.open(url)
        return true
    }
}
