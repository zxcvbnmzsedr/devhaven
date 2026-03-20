struct WorkspaceSurfaceActivity: Equatable {
    let isVisible: Bool
    let isFocused: Bool
}

enum WorkspaceSurfaceActivityPolicy {
    static func activity(
        isWorkspaceVisible: Bool,
        isSelectedTab: Bool,
        windowIsVisible: Bool,
        windowIsKey: Bool,
        focusedPaneID: String?,
        paneID: String
    ) -> WorkspaceSurfaceActivity {
        let isVisible = isWorkspaceVisible && isSelectedTab && windowIsVisible
        let isFocused = isVisible && windowIsKey && focusedPaneID == paneID
        return WorkspaceSurfaceActivity(isVisible: isVisible, isFocused: isFocused)
    }
}
