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
        projection.updateTitle(for: tabID, title: title)
        onChange?()
    }

    public func makeRestoreSnapshot(rootProjectPath: String, isQuickTerminal: Bool) -> ProjectWorkspaceRestoreSnapshot {
        projection.makeRestoreSnapshot(rootProjectPath: rootProjectPath, isQuickTerminal: isQuickTerminal)
    }

    public func restore(from snapshot: ProjectWorkspaceRestoreSnapshot) {
        projection = WorkspaceSessionState(restoring: snapshot)
        onChange?()
    }
}
