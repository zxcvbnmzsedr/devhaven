import Foundation
import Observation

@MainActor
@Observable
public final class GhosttyWorkspaceController {
    public let projectPath: String
    public private(set) var projection: WorkspaceSessionState

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
        projection.createTab()
    }

    public func selectTab(_ tabID: String?) {
        projection.selectTab(tabID)
    }

    public func gotoPreviousTab() {
        projection.gotoPreviousTab()
    }

    public func gotoNextTab() {
        projection.gotoNextTab()
    }

    public func gotoLastTab() {
        projection.gotoLastTab()
    }

    public func gotoTab(at index: Int) {
        projection.gotoTab(at: index)
    }

    public func moveSelectedTab(by amount: Int) {
        projection.moveSelectedTab(by: amount)
    }

    public func moveTab(id: String, by amount: Int) {
        projection.moveTab(id: id, by: amount)
    }

    public func closeTab(_ id: String) {
        projection.closeTab(id)
    }

    public func closeOtherTabs(keeping id: String) {
        projection.closeOtherTabs(keeping: id)
    }

    public func closeTabsToRight(of id: String) {
        projection.closeTabsToRight(of: id)
    }

    @discardableResult
    public func splitFocusedPane(direction: WorkspacePaneSplitDirection) -> WorkspacePaneState? {
        projection.splitFocusedPane(direction: direction)
    }

    public func focusPane(_ paneID: String?) {
        projection.focusPane(paneID)
    }

    public func focusPane(direction: WorkspacePaneFocusDirection) {
        projection.focusPane(direction: direction)
    }

    public func closePane(_ paneID: String?) {
        projection.closePane(paneID)
    }

    public func resizeFocusedPane(direction: WorkspacePaneSplitDirection, amount: UInt16) {
        projection.resizeFocusedPane(direction: direction, amount: amount)
    }

    public func equalizeSelectedTabSplits() {
        projection.equalizeSelectedTabSplits()
    }

    public func toggleZoomOnFocusedPane() {
        projection.toggleZoomOnFocusedPane()
    }

    public func setSelectedTabSplitRatio(at path: WorkspacePaneTree.Path, ratio: Double) {
        projection.setSelectedTabSplitRatio(at: path, ratio: ratio)
    }

    public func updateTitle(for tabID: String, title: String) {
        projection.updateTitle(for: tabID, title: title)
    }
}
