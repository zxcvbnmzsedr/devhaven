import SwiftUI
import GhosttyKit
import DevHavenCore

struct WorkspaceTerminalPaneView: View {
    private enum PaneTabChipLayout {
        static let selectedTitleMaxWidth: CGFloat = 220
        static let unselectedTitleMaxWidth: CGFloat = 150
    }

    let pane: WorkspacePaneState
    let selectedItem: WorkspacePaneItemState
    let terminalModel: GhosttySurfaceHostModel?
    let browserModel: WorkspaceBrowserHostModel?
    let surfaceActivity: WorkspaceSurfaceActivity
    let isFocused: Bool
    let isZoomed: Bool
    let isDraggingPane: Bool
    let dropDirection: WorkspacePaneSplitDirection?
    let draggedItemID: String?
    let itemDropTarget: WorkspacePaneItemChipDropTarget?
    let showsItemMergeTarget: Bool
    let dragCoordinateSpaceName: String
    let onFocusPane: (String) -> Void
    let onSelectItem: (String, String) -> Void
    let onCreateItem: (String) -> Void
    let onCreateBrowserItem: (String) -> Void
    let onCloseItem: (String, String) -> Void
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
    let onPaneDragChanged: (CGPoint) -> Void
    let onPaneDragEnded: (CGPoint) -> Void
    let onPaneItemDragChanged: (String, CGPoint) -> Void
    let onPaneItemDragEnded: (String, CGPoint) -> Void

    init(
        pane: WorkspacePaneState,
        selectedItem: WorkspacePaneItemState? = nil,
        terminalModel: GhosttySurfaceHostModel? = nil,
        browserModel: WorkspaceBrowserHostModel? = nil,
        surfaceActivity: WorkspaceSurfaceActivity,
        isFocused: Bool,
        isZoomed: Bool,
        isDraggingPane: Bool = false,
        dropDirection: WorkspacePaneSplitDirection? = nil,
        draggedItemID: String? = nil,
        itemDropTarget: WorkspacePaneItemChipDropTarget? = nil,
        showsItemMergeTarget: Bool = false,
        dragCoordinateSpaceName: String = "workspace-split-tree-canvas",
        onFocusPane: @escaping (String) -> Void,
        onSelectItem: @escaping (String, String) -> Void = { _, _ in },
        onCreateItem: @escaping (String) -> Void = { _ in },
        onCreateBrowserItem: @escaping (String) -> Void = { _ in },
        onCloseItem: @escaping (String, String) -> Void = { _, _ in },
        onClosePane: @escaping (String) -> Void,
        onSplitPane: @escaping (String, WorkspacePaneSplitDirection) -> Void,
        onFocusDirection: @escaping (String, WorkspacePaneFocusDirection) -> Void,
        onResizePane: @escaping (String, WorkspacePaneSplitDirection, UInt16) -> Void,
        onEqualize: @escaping (String) -> Void,
        onToggleZoom: @escaping (String) -> Void,
        onSurfaceExit: @escaping (String) -> Void,
        onUpdateTabTitle: @escaping (String) -> Void,
        onNewTab: @escaping () -> Bool,
        onCloseTabAction: @escaping (ghostty_action_close_tab_mode_e) -> Bool,
        onGotoTabAction: @escaping (ghostty_action_goto_tab_e) -> Bool,
        onMoveTabAction: @escaping (ghostty_action_move_tab_s) -> Bool,
        onPaneDragChanged: @escaping (CGPoint) -> Void = { _ in },
        onPaneDragEnded: @escaping (CGPoint) -> Void = { _ in },
        onPaneItemDragChanged: @escaping (String, CGPoint) -> Void = { _, _ in },
        onPaneItemDragEnded: @escaping (String, CGPoint) -> Void = { _, _ in }
    ) {
        self.pane = pane
        self.selectedItem = selectedItem ?? pane.selectedItem ?? pane.items.last ?? WorkspacePaneItemState(
            request: pane.request,
            title: pane.selectedTitle
        )
        self.terminalModel = terminalModel
        self.browserModel = browserModel
        self.surfaceActivity = surfaceActivity
        self.isFocused = isFocused
        self.isZoomed = isZoomed
        self.isDraggingPane = isDraggingPane
        self.dropDirection = dropDirection
        self.draggedItemID = draggedItemID
        self.itemDropTarget = itemDropTarget
        self.showsItemMergeTarget = showsItemMergeTarget
        self.dragCoordinateSpaceName = dragCoordinateSpaceName
        self.onFocusPane = onFocusPane
        self.onSelectItem = onSelectItem
        self.onCreateItem = onCreateItem
        self.onCreateBrowserItem = onCreateBrowserItem
        self.onCloseItem = onCloseItem
        self.onClosePane = onClosePane
        self.onSplitPane = onSplitPane
        self.onFocusDirection = onFocusDirection
        self.onResizePane = onResizePane
        self.onEqualize = onEqualize
        self.onToggleZoom = onToggleZoom
        self.onSurfaceExit = onSurfaceExit
        self.onUpdateTabTitle = onUpdateTabTitle
        self.onNewTab = onNewTab
        self.onCloseTabAction = onCloseTabAction
        self.onGotoTabAction = onGotoTabAction
        self.onMoveTabAction = onMoveTabAction
        self.onPaneDragChanged = onPaneDragChanged
        self.onPaneDragEnded = onPaneDragEnded
        self.onPaneItemDragChanged = onPaneItemDragChanged
        self.onPaneItemDragEnded = onPaneItemDragEnded
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(NativeTheme.window)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(isFocused ? NativeTheme.accent.opacity(0.28) : NativeTheme.border.opacity(0.9))
                        .frame(height: 1)
                }

            surfaceHost
                .id(selectedItem.id)
                .padding(.horizontal, 3)
                .padding(.top, 3)
                .padding(.bottom, 3)
                .onAppear {
                    syncSurfaceActivity()
                }
        }
        .background(NativeTheme.surface)
        .clipShape(.rect(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    showsItemMergeTarget
                    ? NativeTheme.accent.opacity(0.55)
                    : NativeTheme.border.opacity(0.95),
                    lineWidth: showsItemMergeTarget ? 1.5 : 1
                )
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(isFocused ? NativeTheme.accent.opacity(0.65) : Color.clear)
                .frame(height: 1)
                .padding(.horizontal, 1)
        }
        .shadow(
            color: showsItemMergeTarget ? NativeTheme.accent.opacity(0.12) : Color.clear,
            radius: 8,
            x: 0,
            y: 0
        )
        .overlay {
            GeometryReader { proxy in
                if shouldShowDockingPreview {
                    paneDockingOverlay(in: proxy.size)
                }
            }
        }
        .opacity(isDraggingPane ? 0.74 : 1)
        .animation(.easeOut(duration: 0.12), value: showsItemMergeTarget)
        .animation(.easeOut(duration: 0.12), value: itemDropTarget?.itemID)
        .animation(.easeOut(duration: 0.12), value: dropDirection)
        .onAppear {
            syncSurfaceActivity()
        }
        .onChange(of: surfaceActivity) { _, _ in
            syncSurfaceActivity()
        }
        .onChange(of: selectedItem.id) { _, _ in
            syncSurfaceActivity()
        }
        .onDisappear {
            terminalModel?.syncSurfaceActivity(isVisible: false, isFocused: false)
        }
    }

    private var surfaceHost: some View {
        Group {
            if selectedItem.isBrowser,
               let browserState = selectedItem.browserState,
               let browserModel {
                WorkspaceBrowserPaneItemView(
                    itemID: selectedItem.id,
                    state: browserState,
                    model: browserModel,
                    isFocused: isFocused,
                    onFocusBrowserItem: {
                        onFocusPane(pane.id)
                        onSelectItem(pane.id, selectedItem.id)
                    }
                )
            } else if let terminalModel {
                GhosttySurfaceHost(
                    model: terminalModel,
                    isFocused: isFocused,
                    chromePolicy: .workspaceMinimal
                )
            } else {
                ContentUnavailableView(
                    "浏览器标签不可用",
                    systemImage: "globe",
                    description: Text("当前浏览器标签状态已失效，请重新打开。")
                )
                .foregroundStyle(NativeTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: 6) {
            paneDragGrip

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(pane.items) { item in
                        paneItemChip(
                            item,
                            isDragged: draggedItemID == item.id,
                            dropEdge: itemDropTarget?.itemID == item.id ? itemDropTarget?.edge : nil
                        )
                    }
                }
            }
            .padding(.horizontal, 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tabStripFrameReporter)
            .overlay {
                if showsItemMergeTarget {
                    mergeTargetOverlay
                }
            }

            paneButton(title: "当前窗格新建终端标签", systemImage: "plus") {
                onFocusPane(pane.id)
                onCreateItem(pane.id)
            }
            paneButton(title: "当前窗格新建浏览器标签", systemImage: "globe") {
                onFocusPane(pane.id)
                onCreateBrowserItem(pane.id)
            }

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

    private var shouldShowDockingPreview: Bool {
        itemDropTarget != nil || showsItemMergeTarget || dropDirection != nil
    }

    @ViewBuilder
    private var paneDragGrip: some View {
        let grip = Color.clear
            .frame(width: 10, height: 18)
            .contentShape(.rect)
            .help("拖动重排窗格")

        if isZoomed {
            grip
        } else {
            grip
                .gesture(
                    DragGesture(minimumDistance: 4, coordinateSpace: .named(dragCoordinateSpaceName))
                        .onChanged { gesture in
                            onFocusPane(pane.id)
                            onPaneDragChanged(gesture.location)
                        }
                        .onEnded { gesture in
                            onPaneDragEnded(gesture.location)
                        }
                )
        }
    }

    private func paneItemChip(
        _ item: WorkspacePaneItemState,
        isDragged: Bool,
        dropEdge: WorkspacePaneItemDropEdge?
    ) -> some View {
        let isSelected = item.id == selectedItem.id

        return HStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: item.isBrowser ? "globe" : "terminal")
                    .font(.system(size: 10, weight: .medium))
                Text(displayTitle(for: item))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(
                minWidth: 0,
                maxWidth: isSelected
                    ? PaneTabChipLayout.selectedTitleMaxWidth
                    : PaneTabChipLayout.unselectedTitleMaxWidth,
                alignment: .leading
            )
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isSelected ? NativeTheme.textPrimary : NativeTheme.textSecondary)
            .contentShape(.rect)
            .onTapGesture {
                onFocusPane(pane.id)
                onSelectItem(pane.id, item.id)
            }
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named(dragCoordinateSpaceName))
                    .onChanged { gesture in
                        onFocusPane(pane.id)
                        onSelectItem(pane.id, item.id)
                        onPaneItemDragChanged(item.id, gesture.location)
                    }
                    .onEnded { gesture in
                        onPaneItemDragEnded(item.id, gesture.location)
                    }
            )

            Button {
                onFocusPane(pane.id)
                onCloseItem(pane.id, item.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isSelected ? NativeTheme.textPrimary : NativeTheme.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
        .background(isSelected ? NativeTheme.elevated.opacity(0.92) : NativeTheme.window.opacity(0.4))
        .help(displayTitle(for: item))
        .overlay {
            if draggedItemID != nil,
               itemDropTarget?.itemID == item.id {
                RoundedRectangle(cornerRadius: 5)
                    .fill(NativeTheme.accent.opacity(0.08))
                    .padding(1)
            }
        }
        .clipShape(.rect(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(
                    isSelected ? NativeTheme.accent.opacity(0.3) : NativeTheme.border.opacity(0.6),
                    lineWidth: 1
                )
        }
        .overlay(alignment: dropEdge == .trailing ? .trailing : .leading) {
            if let dropEdge,
               draggedItemID != item.id || dropEdge == .leading {
                Rectangle()
                    .fill(NativeTheme.accent.opacity(0.95))
                    .frame(width: 2)
                    .padding(.vertical, 2)
                    .shadow(color: NativeTheme.accent.opacity(0.35), radius: 2, x: 0, y: 0)
            }
        }
        .opacity(isDragged ? 0.48 : 1)
        .scaleEffect(isDragged ? 0.985 : 1)
        .background(itemFrameReporter(for: item))
        .contentShape(.rect)
    }

    private var mergeTargetOverlay: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(NativeTheme.accent.opacity(0.12))
            .padding(.vertical, 2)
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(NativeTheme.accent.opacity(0.65), lineWidth: 1)
                    .padding(.vertical, 2)
            }
            .overlay {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.left.and.arrow.up.right")
                        .font(.system(size: 10, weight: .semibold))
                    Text("移入当前组")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(NativeTheme.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(NativeTheme.window.opacity(0.92))
                )
                .shadow(color: NativeTheme.accent.opacity(0.12), radius: 4, x: 0, y: 1)
            }
            .allowsHitTesting(false)
    }

    private var tabStripFrameReporter: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: WorkspacePaneTabStripFramePreferenceKey.self,
                value: [
                    WorkspacePaneTabStripFramePreference(
                        paneID: pane.id,
                        frame: proxy.frame(in: .named(dragCoordinateSpaceName))
                    )
                ]
            )
        }
    }

    private func itemFrameReporter(for item: WorkspacePaneItemState) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: WorkspacePaneItemFramePreferenceKey.self,
                value: [
                    WorkspacePaneItemFramePreference(
                        paneID: pane.id,
                        itemID: item.id,
                        frame: proxy.frame(in: .named(dragCoordinateSpaceName))
                    )
                ]
            )
        }
    }

    private func paneButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(NativeTheme.textSecondary)
                .frame(width: 20, height: 20)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(title)
    }

    @ViewBuilder
    private func paneDockingOverlay(in size: CGSize) -> some View {
        let showsEdgeTargets = dropDirection != nil || showsItemMergeTarget

        ZStack {
            if showsEdgeTargets {
                paneDockZone(in: size, direction: .left, isActive: dropDirection == .left)
                paneDockZone(in: size, direction: .right, isActive: dropDirection == .right)
                paneDockZone(in: size, direction: .top, isActive: dropDirection == .top)
                paneDockZone(in: size, direction: .down, isActive: dropDirection == .down)
            }

            if draggedItemID != nil, showsEdgeTargets || showsItemMergeTarget {
                paneMergeZone(in: size, isActive: showsItemMergeTarget)
            }
        }
        .overlay(alignment: .top) {
            if itemDropTarget != nil {
                dockStatusPill(title: "插入标签栏")
                    .padding(.top, 52)
            }
        }
        .overlay(alignment: paneDropAlignment(for: dropDirection ?? .right)) {
            if let dropDirection {
                dockStatusPill(title: splitDropLabel(for: dropDirection))
                    .padding(12)
            }
        }
        .overlay {
            if showsItemMergeTarget {
                dockStatusPill(title: "并入当前组")
            }
        }
        .allowsHitTesting(false)
    }

    private func paneDockZone(
        in size: CGSize,
        direction: WorkspacePaneSplitDirection,
        isActive: Bool
    ) -> some View {
        let frame = paneDockZoneFrame(in: size, direction: direction)

        return RoundedRectangle(cornerRadius: 8)
            .fill(NativeTheme.accent.opacity(isActive ? 0.18 : 0.06))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(NativeTheme.accent.opacity(isActive ? 0.65 : 0.2), lineWidth: isActive ? 1.2 : 1)
            }
            .frame(width: frame.width, height: frame.height)
            .offset(
                x: frame.midX - size.width / 2,
                y: frame.midY - size.height / 2
            )
    }

    private func paneMergeZone(
        in size: CGSize,
        isActive: Bool
    ) -> some View {
        let width = max(120, min(size.width * 0.36, 220))
        let height = max(72, min(size.height * 0.22, 120))

        return RoundedRectangle(cornerRadius: 10)
            .fill(NativeTheme.accent.opacity(isActive ? 0.16 : 0.05))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(NativeTheme.accent.opacity(isActive ? 0.65 : 0.22), style: StrokeStyle(lineWidth: isActive ? 1.25 : 1, dash: isActive ? [] : [5, 4]))
            }
            .frame(width: width, height: height)
    }

    private func paneDockZoneFrame(
        in size: CGSize,
        direction: WorkspacePaneSplitDirection
    ) -> CGRect {
        let inset: CGFloat = 10
        let horizontalThickness = max(48, min(size.width * 0.2, 92))
        let verticalThickness = max(40, min(size.height * 0.2, 84))

        switch direction {
        case .left:
            return CGRect(
                x: inset,
                y: inset,
                width: max(0, horizontalThickness),
                height: max(0, size.height - inset * 2)
            )
        case .right:
            return CGRect(
                x: max(inset, size.width - horizontalThickness - inset),
                y: inset,
                width: max(0, horizontalThickness),
                height: max(0, size.height - inset * 2)
            )
        case .top:
            return CGRect(
                x: inset,
                y: inset,
                width: max(0, size.width - inset * 2),
                height: max(0, verticalThickness)
            )
        case .down:
            return CGRect(
                x: inset,
                y: max(inset, size.height - verticalThickness - inset),
                width: max(0, size.width - inset * 2),
                height: max(0, verticalThickness)
            )
        }
    }

    private func dockStatusPill(title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(NativeTheme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(NativeTheme.window.opacity(0.94))
            )
            .overlay {
                Capsule()
                    .stroke(NativeTheme.accent.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: NativeTheme.accent.opacity(0.12), radius: 4, x: 0, y: 1)
    }

    private func paneDropAlignment(for direction: WorkspacePaneSplitDirection) -> Alignment {
        switch direction {
        case .left:
            return .leading
        case .right:
            return .trailing
        case .top:
            return .top
        case .down:
            return .bottom
        }
    }

    private func splitDropLabel(for direction: WorkspacePaneSplitDirection) -> String {
        switch direction {
        case .left:
            return "拆分到左侧"
        case .right:
            return "拆分到右侧"
        case .top:
            return "拆分到上方"
        case .down:
            return "拆分到下方"
        }
    }

    private func splitDropReleaseText(for direction: WorkspacePaneSplitDirection) -> String {
        switch direction {
        case .left:
            return "释放后停靠到左侧并形成新组"
        case .right:
            return "释放后停靠到右侧并形成新组"
        case .top:
            return "释放后停靠到上方并形成新组"
        case .down:
            return "释放后停靠到下方并形成新组"
        }
    }

    private func syncSurfaceActivity() {
        guard let terminalModel else {
            return
        }
        terminalModel.syncSurfaceActivity(
            isVisible: surfaceActivity.isVisible,
            isFocused: surfaceActivity.isFocused
        )
        if surfaceActivity.isFocused {
            terminalModel.restoreWindowResponderIfNeeded()
        }
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

    private func displayTitle(for item: WorkspacePaneItemState) -> String {
        guard item.id == selectedItem.id,
              item.isTerminal,
              let terminalModel else {
            return item.title
        }
        return terminalModel.displayTitle(fallback: item.title)
    }
}

enum WorkspacePaneItemDropEdge {
    case leading
    case trailing
}

struct WorkspacePaneItemChipDropTarget: Equatable {
    let itemID: String
    let edge: WorkspacePaneItemDropEdge
}

struct WorkspacePaneItemFramePreference: Equatable {
    let paneID: String
    let itemID: String
    let frame: CGRect
}

struct WorkspacePaneTabStripFramePreference: Equatable {
    let paneID: String
    let frame: CGRect
}

struct WorkspacePaneItemFramePreferenceKey: PreferenceKey {
    static let defaultValue: [WorkspacePaneItemFramePreference] = []

    static func reduce(value: inout [WorkspacePaneItemFramePreference], nextValue: () -> [WorkspacePaneItemFramePreference]) {
        value.append(contentsOf: nextValue())
    }
}

struct WorkspacePaneTabStripFramePreferenceKey: PreferenceKey {
    static let defaultValue: [WorkspacePaneTabStripFramePreference] = []

    static func reduce(value: inout [WorkspacePaneTabStripFramePreference], nextValue: () -> [WorkspacePaneTabStripFramePreference]) {
        value.append(contentsOf: nextValue())
    }
}
