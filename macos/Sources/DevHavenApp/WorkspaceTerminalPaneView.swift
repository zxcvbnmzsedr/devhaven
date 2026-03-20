import SwiftUI
import GhosttyKit
import DevHavenCore

struct WorkspaceTerminalPaneView: View {
    let pane: WorkspacePaneState
    let isFocused: Bool
    let isZoomed: Bool
    let onFocusPane: (String) -> Void
    let onClosePane: (String) -> Void
    let onSplitPane: (String, WorkspacePaneSplitDirection) -> Void
    let onFocusDirection: (String, WorkspacePaneFocusDirection) -> Void
    let onResizePane: (String, WorkspacePaneSplitDirection, UInt16) -> Void
    let onEqualize: (String) -> Void
    let onToggleZoom: (String) -> Void
    let onSurfaceExit: (String) -> Void
    let onUpdateTabTitle: (String) -> Void
    let onNewTab: () -> Bool
    let onCloseTabAction: (ghostty_action_close_tab_mode_e) -> Bool
    let onGotoTabAction: (ghostty_action_goto_tab_e) -> Bool
    let onMoveTabAction: (ghostty_action_move_tab_s) -> Bool

    var body: some View {
        VStack(spacing: 10) {
            header
            GhosttySurfaceHost(
                request: pane.request,
                isFocused: isFocused,
                onFocusChange: { focused in
                    guard focused else { return }
                    onFocusPane(pane.id)
                },
                onSurfaceExit: {
                    onSurfaceExit(pane.id)
                },
                onTabTitleChange: onUpdateTabTitle,
                onNewTab: onNewTab,
                onCloseTab: onCloseTabAction,
                onGotoTab: onGotoTabAction,
                onMoveTab: onMoveTabAction,
                onSplitAction: handleSplitAction
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(10)
        .background(NativeTheme.surface)
        .clipShape(.rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isFocused ? NativeTheme.accent.opacity(0.8) : NativeTheme.border, lineWidth: isFocused ? 2 : 1)
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(isZoomed ? "已放大窗格" : (isFocused ? "当前窗格" : "窗格"), systemImage: isFocused ? "command" : "rectangle.split.1x2")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isFocused ? NativeTheme.textPrimary : NativeTheme.textSecondary)
            Spacer(minLength: 0)
            paneButton(title: "左右分屏", systemImage: "square.split.2x1") {
                onFocusPane(pane.id)
                onSplitPane(pane.id, .right)
            }
            paneButton(title: "上下分屏", systemImage: "rectangle.split.1x2") {
                onFocusPane(pane.id)
                onSplitPane(pane.id, .down)
            }
            paneButton(title: isZoomed ? "还原窗格" : "放大窗格", systemImage: isZoomed ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") {
                onFocusPane(pane.id)
                onToggleZoom(pane.id)
            }
            paneButton(title: "平均分配", systemImage: "square.grid.2x2") {
                onFocusPane(pane.id)
                onEqualize(pane.id)
            }
            paneButton(title: "关闭窗格", systemImage: "xmark") {
                onClosePane(pane.id)
            }
        }
    }

    private func paneButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(NativeTheme.textSecondary)
                .frame(width: 26, height: 26)
                .background(NativeTheme.window)
                .clipShape(.rect(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(title)
    }

    private func handleSplitAction(_ action: GhosttySplitAction) -> Bool {
        onFocusPane(pane.id)
        switch action {
        case let .newSplit(direction):
            onSplitPane(pane.id, direction)
            return true
        case let .gotoSplit(direction):
            onFocusDirection(pane.id, direction)
            return true
        case let .resizeSplit(direction, amount):
            onResizePane(pane.id, direction, amount)
            return true
        case .equalizeSplits:
            onEqualize(pane.id)
            return true
        case .toggleSplitZoom:
            onToggleZoom(pane.id)
            return true
        }
    }
}
