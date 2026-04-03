import Foundation
import Observation

@MainActor
@Observable
public final class GhosttyWorkspaceController {
    public let projectPath: String
    public private(set) var projection: WorkspaceSessionState
    public var onChange: (() -> Void)?

    public init(
        projectPath: String,
        workspaceId: String = "workspace:\(UUID().uuidString.lowercased())"
    ) {
        self.projectPath = projectPath
        self.projection = WorkspaceSessionState(projectPath: projectPath, workspaceId: workspaceId)
    }

    public var workspaceId: String {
        projection.workspaceId
    }

    public var sessionState: WorkspaceSessionState {
        projection
    }

    public var tabs: [WorkspaceTabState] {
        projection.tabs
    }

    public var selectedTabId: String? {
        projection.selectedTabId
    }

    public var selectedTab: WorkspaceTabState? {
        projection.selectedTab
    }

    public var selectedPane: WorkspacePaneState? {
        projection.selectedPane
    }

    public var selectedPaneItem: WorkspacePaneItemState? {
        projection.selectedPaneItem
    }

    public var tabCount: Int {
        projection.tabs.count
    }

    public var paneCount: Int {
        projection.tabs.reduce(into: 0) { partialResult, tab in
            partialResult += tab.leaves.count
        }
    }

    @discardableResult
    public func createTab() -> WorkspaceTabState {
        let tab = projection.createTab()
        onChange?()
        return tab
    }

    public func selectTab(_ tabID: String?) {
        projection.selectTab(tabID)
        onChange?()
    }

    public func gotoPreviousTab() {
        projection.gotoPreviousTab()
        onChange?()
    }

    public func gotoNextTab() {
        projection.gotoNextTab()
        onChange?()
    }

    public func gotoLastTab() {
        projection.gotoLastTab()
        onChange?()
    }

    public func gotoTab(at index: Int) {
        projection.gotoTab(at: index)
        onChange?()
    }

    public func moveSelectedTab(by amount: Int) {
        projection.moveSelectedTab(by: amount)
        onChange?()
    }

    public func moveTab(id: String, by amount: Int) {
        projection.moveTab(id: id, by: amount)
        onChange?()
    }

    public func closeTab(_ id: String) {
        projection.closeTab(id)
        onChange?()
    }

    public func closeTabAllowingEmpty(_ id: String) {
        projection.closeTabAllowingEmpty(id)
        onChange?()
    }

    public func closeOtherTabs(keeping id: String) {
        projection.closeOtherTabs(keeping: id)
        onChange?()
    }

    public func closeTabsToRight(of id: String) {
        projection.closeTabsToRight(of: id)
        onChange?()
    }

    @discardableResult
    public func splitFocusedPane(direction: WorkspacePaneSplitDirection) -> WorkspacePaneState? {
        let pane = projection.splitFocusedPane(direction: direction)
        if pane != nil {
            onChange?()
        }
        return pane
    }

    @discardableResult
    public func createTerminalItem(inPane paneID: String?) -> WorkspacePaneItemState? {
        let item = projection.createTerminalItem(inPane: paneID)
        if item != nil {
            onChange?()
        }
        return item
    }

    public func selectPaneItem(inPane paneID: String?, itemID: String?) {
        projection.selectPaneItem(paneID: paneID, itemID: itemID)
        onChange?()
    }

    public func gotoPreviousPaneItem(inPane paneID: String?) {
        projection.gotoPreviousPaneItem(inPane: paneID)
        onChange?()
    }

    public func gotoNextPaneItem(inPane paneID: String?) {
        projection.gotoNextPaneItem(inPane: paneID)
        onChange?()
    }

    public func gotoLastPaneItem(inPane paneID: String?) {
        projection.gotoLastPaneItem(inPane: paneID)
        onChange?()
    }

    public func gotoPaneItem(at index: Int, inPane paneID: String?) {
        projection.gotoPaneItem(at: index, inPane: paneID)
        onChange?()
    }

    public func movePaneItem(inPane paneID: String?, itemID: String?, by amount: Int) {
        projection.movePaneItem(inPane: paneID, itemID: itemID, by: amount)
        onChange?()
    }

    @discardableResult
    public func movePaneItem(
        _ itemID: String?,
        from sourcePaneID: String?,
        to targetPaneID: String?,
        at targetIndex: Int? = nil
    ) -> WorkspacePaneItemState? {
        let item = projection.movePaneItem(itemID, from: sourcePaneID, to: targetPaneID, at: targetIndex)
        if item != nil {
            onChange?()
        }
        return item
    }

    @discardableResult
    public func splitPaneItem(
        _ itemID: String?,
        from sourcePaneID: String?,
        beside anchorPaneID: String?,
        direction: WorkspacePaneSplitDirection
    ) -> WorkspacePaneState? {
        let pane = projection.splitPaneItem(itemID, from: sourcePaneID, beside: anchorPaneID, direction: direction)
        if pane != nil {
            onChange?()
        }
        return pane
    }

    public func movePane(
        _ paneID: String?,
        beside targetPaneID: String?,
        direction: WorkspacePaneSplitDirection
    ) {
        projection.movePane(paneID, beside: targetPaneID, direction: direction)
        onChange?()
    }

    public func closeOtherPaneItems(inPane paneID: String?, keeping itemID: String?) {
        projection.closeOtherPaneItems(inPane: paneID, keeping: itemID)
        onChange?()
    }

    public func closePaneItemsToRight(inPane paneID: String?, of itemID: String?) {
        projection.closePaneItemsToRight(inPane: paneID, of: itemID)
        onChange?()
    }

    public func closePaneItem(inPane paneID: String?, itemID: String?) {
        projection.closePaneItem(paneID: paneID, itemID: itemID)
        onChange?()
    }

    public func focusPane(_ paneID: String?) {
        projection.focusPane(paneID)
        onChange?()
    }

    public func focusPane(direction: WorkspacePaneFocusDirection) {
        projection.focusPane(direction: direction)
        onChange?()
    }

    public func closePane(_ paneID: String?) {
        projection.closePane(paneID)
        onChange?()
    }

    public func resizeFocusedPane(direction: WorkspacePaneSplitDirection, amount: UInt16) {
        projection.resizeFocusedPane(direction: direction, amount: amount)
        onChange?()
    }

    public func equalizeSelectedTabSplits() {
        projection.equalizeSelectedTabSplits()
        onChange?()
    }

    public func toggleZoomOnFocusedPane() {
        projection.toggleZoomOnFocusedPane()
        onChange?()
    }

    public func setSelectedTabSplitRatio(at path: WorkspacePaneTree.Path, ratio: Double) {
        projection.setSelectedTabSplitRatio(at: path, ratio: ratio)
        onChange?()
    }

    public func updateTitle(for tabID: String, title: String) {
        guard let previousTitle = projection.tabs.first(where: { $0.id == tabID })?.title else {
            return
        }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        let resolvedTitle = WorkspaceTabTitlePolicy.resolveRuntimeTitle(
            currentTitle: previousTitle,
            runtimeTitle: trimmed
        )
        guard previousTitle != resolvedTitle else {
            return
        }
        projection.updateTitle(for: tabID, title: title)
        let nextTitle = projection.tabs.first(where: { $0.id == tabID })?.title
        guard previousTitle != nextTitle else {
            return
        }
        onChange?()
    }

    public func updatePaneItemTitle(inPane paneID: String?, itemID: String?, title: String) {
        projection.updatePaneItemTitle(inPane: paneID, itemID: itemID, title: title)
        onChange?()
    }

    public func makeRestoreSnapshot(
        rootProjectPath: String,
        isQuickTerminal: Bool,
        workspaceRootContext: WorkspaceRootSessionContext?,
        workspaceAlignmentGroupID: String?
    ) -> ProjectWorkspaceRestoreSnapshot {
        projection.makeRestoreSnapshot(
            rootProjectPath: rootProjectPath,
            isQuickTerminal: isQuickTerminal,
            workspaceRootContext: workspaceRootContext,
            workspaceAlignmentGroupID: workspaceAlignmentGroupID
        )
    }

    public func restore(from snapshot: ProjectWorkspaceRestoreSnapshot) {
        projection = WorkspaceSessionState(restoring: snapshot)
        onChange?()
    }
}
