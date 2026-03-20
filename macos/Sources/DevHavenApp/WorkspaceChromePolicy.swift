import Foundation

struct WorkspaceChromePolicy: Equatable {
    let showsGlobalSidebar: Bool
    let showsWorkspaceHeader: Bool
    let showsPaneHeader: Bool
    let showsSurfaceStatusBar: Bool

    static let standard = WorkspaceChromePolicy(
        showsGlobalSidebar: true,
        showsWorkspaceHeader: true,
        showsPaneHeader: true,
        showsSurfaceStatusBar: true
    )

    static let workspaceMinimal = WorkspaceChromePolicy(
        showsGlobalSidebar: false,
        showsWorkspaceHeader: false,
        showsPaneHeader: false,
        showsSurfaceStatusBar: false
    )

    static func resolve(isWorkspacePresented: Bool) -> WorkspaceChromePolicy {
        isWorkspacePresented ? .workspaceMinimal : .standard
    }
}
