import AppKit
import Foundation
import GhosttyKit
import DevHavenCore

enum GhosttySplitAction: Equatable {
    case newSplit(direction: WorkspacePaneSplitDirection)
    case gotoSplit(direction: WorkspacePaneFocusDirection)
    case resizeSplit(direction: WorkspacePaneSplitDirection, amount: UInt16)
    case equalizeSplits
    case toggleSplitZoom
}

final class GhosttySurfaceBridge {
    let state = GhosttySurfaceState()

    weak var surfaceView: GhosttyTerminalSurfaceView?
    var surface: ghostty_surface_t?

    var onNewTab: (() -> Bool)?
    var onCloseTab: ((ghostty_action_close_tab_mode_e) -> Bool)?
    var onGotoTab: ((ghostty_action_goto_tab_e) -> Bool)?
    var onMoveTab: ((ghostty_action_move_tab_s) -> Bool)?
    var onSplitAction: ((GhosttySplitAction) -> Bool)?
    var onTitleChange: ((String) -> Void)?
    var onWorkingDirectoryChange: ((String) -> Void)?
    var onRendererHealthChange: ((Bool) -> Void)?
    var onAppearanceChange: ((GhosttySurfaceAppearance) -> Void)?
    var onDesktopNotification: ((String, String) -> Void)?
    var onTaskStatusChange: ((GhosttySurfaceTaskStatus) -> Void)?
    var onBell: (() -> Void)?
    var onCloseRequest: ((Bool) -> Void)?

    @MainActor
    func handleAction(target: ghostty_target_s, action: ghostty_action_s) -> Bool {
        _ = target

        if let handled = handleTabAction(action) {
            return handled
        }

        if let handled = handleSplitAction(action) {
            return handled
        }

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

        case GHOSTTY_ACTION_SCROLLBAR:
            let scroll = action.action.scrollbar
            surfaceView?.updateScrollbar(
                total: scroll.total,
                offset: scroll.offset,
                length: scroll.len
            )
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

        case GHOSTTY_ACTION_DESKTOP_NOTIFICATION:
            let note = action.action.desktop_notification
            let title = string(from: note.title) ?? ""
            let body = string(from: note.body) ?? ""
            guard !(title.isEmpty && body.isEmpty) else {
                return true
            }
            onDesktopNotification?(title, body)
            return true

        case GHOSTTY_ACTION_PROGRESS_REPORT:
            let status = taskStatus(from: action.action.progress_report.state)
            guard status != state.taskStatus else {
                return true
            }
            state.taskStatus = status
            onTaskStatusChange?(status)
            return true

        case GHOSTTY_ACTION_RING_BELL:
            state.bellCount += 1
            onBell?()
            return true

        default:
            return false
        }
    }

    private func handleTabAction(_ action: ghostty_action_s) -> Bool? {
        switch action.tag {
        case GHOSTTY_ACTION_NEW_TAB:
            return onNewTab?() ?? false

        case GHOSTTY_ACTION_CLOSE_TAB:
            return onCloseTab?(action.action.close_tab_mode) ?? false

        case GHOSTTY_ACTION_GOTO_TAB:
            return onGotoTab?(action.action.goto_tab) ?? false

        case GHOSTTY_ACTION_MOVE_TAB:
            return onMoveTab?(action.action.move_tab) ?? false

        default:
            return nil
        }
    }

    private func handleSplitAction(_ action: ghostty_action_s) -> Bool? {
        switch action.tag {
        case GHOSTTY_ACTION_NEW_SPLIT:
            guard let direction = splitDirection(from: action.action.new_split) else {
                return false
            }
            return onSplitAction?(.newSplit(direction: direction)) ?? false

        case GHOSTTY_ACTION_GOTO_SPLIT:
            guard let direction = focusDirection(from: action.action.goto_split) else {
                return false
            }
            return onSplitAction?(.gotoSplit(direction: direction)) ?? false

        case GHOSTTY_ACTION_RESIZE_SPLIT:
            let resize = action.action.resize_split
            guard let direction = resizeDirection(from: resize.direction) else {
                return false
            }
            return onSplitAction?(.resizeSplit(direction: direction, amount: resize.amount)) ?? false

        case GHOSTTY_ACTION_EQUALIZE_SPLITS:
            return onSplitAction?(.equalizeSplits) ?? false

        case GHOSTTY_ACTION_TOGGLE_SPLIT_ZOOM:
            return onSplitAction?(.toggleSplitZoom) ?? false

        default:
            return nil
        }
    }

    private func splitDirection(from value: ghostty_action_split_direction_e) -> WorkspacePaneSplitDirection? {
        switch value {
        case GHOSTTY_SPLIT_DIRECTION_LEFT:
            return .left
        case GHOSTTY_SPLIT_DIRECTION_RIGHT:
            return .right
        case GHOSTTY_SPLIT_DIRECTION_UP:
            return .top
        case GHOSTTY_SPLIT_DIRECTION_DOWN:
            return .down
        default:
            return nil
        }
    }

    private func focusDirection(from value: ghostty_action_goto_split_e) -> WorkspacePaneFocusDirection? {
        switch value {
        case GHOSTTY_GOTO_SPLIT_PREVIOUS:
            return .previous
        case GHOSTTY_GOTO_SPLIT_NEXT:
            return .next
        case GHOSTTY_GOTO_SPLIT_LEFT:
            return .left
        case GHOSTTY_GOTO_SPLIT_RIGHT:
            return .right
        case GHOSTTY_GOTO_SPLIT_UP:
            return .top
        case GHOSTTY_GOTO_SPLIT_DOWN:
            return .down
        default:
            return nil
        }
    }

    private func resizeDirection(from value: ghostty_action_resize_split_direction_e) -> WorkspacePaneSplitDirection? {
        switch value {
        case GHOSTTY_RESIZE_SPLIT_LEFT:
            return .left
        case GHOSTTY_RESIZE_SPLIT_RIGHT:
            return .right
        case GHOSTTY_RESIZE_SPLIT_UP:
            return .top
        case GHOSTTY_RESIZE_SPLIT_DOWN:
            return .down
        default:
            return nil
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

    private func taskStatus(from progressState: ghostty_action_progress_report_state_e) -> GhosttySurfaceTaskStatus {
        switch progressState {
        case GHOSTTY_PROGRESS_STATE_SET,
             GHOSTTY_PROGRESS_STATE_ERROR,
             GHOSTTY_PROGRESS_STATE_INDETERMINATE,
             GHOSTTY_PROGRESS_STATE_PAUSE:
            return .running
        case GHOSTTY_PROGRESS_STATE_REMOVE:
            return .idle
        default:
            return .idle
        }
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
