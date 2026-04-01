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
    var onContentInvalidated: (() -> Void)?
    var onCloseRequest: ((Bool) -> Void)?

    /// Minimum interval between content invalidation callbacks to avoid
    /// flooding the snapshot chain during high-frequency Ghostty wakeups.
    private static let contentInvalidationThrottleInterval: TimeInterval = 0.2
    private var lastContentInvalidationTime: CFAbsoluteTime = 0

    func invalidateRenderedContent() {
        guard let onContentInvalidated else {
            return
        }
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastContentInvalidationTime >= Self.contentInvalidationThrottleInterval else {
            return
        }
        lastContentInvalidationTime = now
        onContentInvalidated()
    }

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
            guard state.title != title else {
                return true
            }
            state.title = title
            onTitleChange?(title)
            return true

        case GHOSTTY_ACTION_PWD:
            guard let path = string(from: action.action.pwd.pwd) else {
                return true
            }
            guard state.pwd != path else {
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
            guard state.rendererHealthy != healthy else {
                return true
            }
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

        case GHOSTTY_ACTION_START_SEARCH:
            let needle = string(from: action.action.start_search.needle) ?? ""
            if !needle.isEmpty {
                state.searchNeedle = needle
            } else if state.searchNeedle == nil {
                state.searchNeedle = ""
            }
            state.searchTotal = nil
            state.searchSelected = nil
            state.searchFocusCount += 1
            return true

        case GHOSTTY_ACTION_END_SEARCH:
            state.searchNeedle = nil
            state.searchTotal = nil
            state.searchSelected = nil
            return true

        case GHOSTTY_ACTION_SEARCH_TOTAL:
            let total = action.action.search_total.total
            state.searchTotal = total < 0 ? nil : Int(total)
            return true

        case GHOSTTY_ACTION_SEARCH_SELECTED:
            let selected = action.action.search_selected.selected
            state.searchSelected = selected < 0 ? nil : Int(selected)
            return true

        case GHOSTTY_ACTION_CONFIG_CHANGE:
            let appearance = GhosttySurfaceAppearance(config: action.action.config_change.config)
            guard state.appearance != appearance else {
                return true
            }
            state.appearance = appearance
            onAppearanceChange?(appearance)
            return true

        case GHOSTTY_ACTION_COLOR_CHANGE:
            let appearance = GhosttySurfaceAppearance(
                backgroundColorChange: action.action.color_change,
                fallback: state.appearance
            )
            guard state.appearance != appearance else {
                return true
            }
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
        guard let string = String(data: data, encoding: .utf8),
              let url = Self.resolvedOpenURL(from: string, workingDirectory: state.pwd)
        else {
            return false
        }

        return NSWorkspace.shared.open(url)
    }

    static func resolvedOpenURL(from rawString: String, workingDirectory: String?) -> URL? {
        let trimmed = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let assignmentValue = shellAssignmentValue(in: trimmed) {
            return resolvedOpenURL(from: assignmentValue, workingDirectory: workingDirectory)
        }

        if let url = URL(string: trimmed), let scheme = url.scheme, !scheme.isEmpty {
            return url
        }

        if let fileURL = resolvedFileURL(from: trimmed, workingDirectory: workingDirectory) {
            return fileURL
        }

        return URL(string: trimmed)
    }

    private static func shellAssignmentValue(in string: String) -> String? {
        guard let separatorIndex = string.firstIndex(of: "=") else {
            return nil
        }

        let key = String(string[..<separatorIndex])
        guard isShellVariableName(key) else {
            return nil
        }

        let valueStart = string.index(after: separatorIndex)
        let value = String(string[valueStart...])
        guard isPathLike(value) else {
            return nil
        }
        return value
    }

    private static func resolvedFileURL(from string: String, workingDirectory: String?) -> URL? {
        if string == "~" || string.hasPrefix("~/") {
            return URL(fileURLWithPath: (string as NSString).expandingTildeInPath)
        }

        if string.hasPrefix("/") {
            return URL(fileURLWithPath: string)
        }

        guard let workingDirectory, isRelativePath(string) else {
            return nil
        }

        return URL(fileURLWithPath: string, relativeTo: URL(fileURLWithPath: workingDirectory, isDirectory: true))
            .standardizedFileURL
    }

    private static func isShellVariableName(_ string: String) -> Bool {
        guard let first = string.first, first == "_" || first.isLetter else {
            return false
        }
        return string.dropFirst().allSatisfy { $0 == "_" || $0.isLetter || $0.isNumber }
    }

    private static func isPathLike(_ string: String) -> Bool {
        string.hasPrefix("/")
            || string == "~"
            || string.hasPrefix("~/")
            || isRelativePath(string)
            || string.hasPrefix("file://")
    }

    private static func isRelativePath(_ string: String) -> Bool {
        string == "."
            || string == ".."
            || string.hasPrefix("./")
            || string.hasPrefix("../")
    }
}
