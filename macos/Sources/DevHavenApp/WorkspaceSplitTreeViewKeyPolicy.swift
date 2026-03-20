enum WorkspaceSplitTreeViewKeyPolicy {
    /// DevHaven 的 pane 内容由外部 store 持有 `GhosttySurfaceHostModel` / `GhosttyTerminalSurfaceView`，
    /// 不能像 supacode 那样把 subtree 容器按结构重建；否则单 pane -> 双 pane 时会把已挂载 pane 一起 remount，
    /// 表现成原 pane 内容瞬间消失。
    static let shouldKeyRootByStructuralIdentity = false
    static let shouldKeySplitSubtreeByStructuralIdentity = false
}
