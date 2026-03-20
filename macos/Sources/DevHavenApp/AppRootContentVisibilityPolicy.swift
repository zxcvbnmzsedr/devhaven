import Foundation

struct AppRootContentVisibilityPolicy: Equatable {
    let keepsMainContentMounted: Bool
    let keepsWorkspaceMounted: Bool
    let mainContentOpacity: Double
    let mainContentAllowsHitTesting: Bool
    let workspaceContentOpacity: Double
    let workspaceContentAllowsHitTesting: Bool

    static func resolve(isWorkspacePresented: Bool) -> AppRootContentVisibilityPolicy {
        AppRootContentVisibilityPolicy(
            keepsMainContentMounted: true,
            keepsWorkspaceMounted: true,
            mainContentOpacity: isWorkspacePresented ? 0 : 1,
            mainContentAllowsHitTesting: !isWorkspacePresented,
            workspaceContentOpacity: isWorkspacePresented ? 1 : 0,
            workspaceContentAllowsHitTesting: isWorkspacePresented
        )
    }
}
