import Foundation

public enum WorkspaceTabTitlePolicy {
    public static func defaultTitle(for index: Int) -> String {
        "终端\(index)"
    }

    public static func resolveRuntimeTitle(currentTitle: String, runtimeTitle: String?) -> String {
        _ = runtimeTitle
        return currentTitle
    }
}
