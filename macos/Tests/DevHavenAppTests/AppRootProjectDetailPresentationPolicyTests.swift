import XCTest
@testable import DevHavenApp

final class AppRootProjectDetailPresentationPolicyTests: XCTestCase {
    func testHomePageUsesPersistentSidebarForSelectedProject() {
        let policy = AppRootProjectDetailPresentationPolicy.resolve(
            isWorkspacePresented: false,
            selectedProjectExists: true,
            isDetailPanelRequested: false
        )

        XCTAssertEqual(
            policy,
            AppRootProjectDetailPresentationPolicy(
                showsPersistentSidebar: true,
                showsDismissableOverlay: false
            )
        )
    }

    func testWorkspaceRespectsDismissableOverlayRequest() {
        let policy = AppRootProjectDetailPresentationPolicy.resolve(
            isWorkspacePresented: true,
            selectedProjectExists: true,
            isDetailPanelRequested: true
        )

        XCTAssertEqual(
            policy,
            AppRootProjectDetailPresentationPolicy(
                showsPersistentSidebar: false,
                showsDismissableOverlay: true
            )
        )
    }

    func testNoSelectedProjectShowsNoDetailPresentation() {
        let policy = AppRootProjectDetailPresentationPolicy.resolve(
            isWorkspacePresented: false,
            selectedProjectExists: false,
            isDetailPanelRequested: true
        )

        XCTAssertEqual(
            policy,
            AppRootProjectDetailPresentationPolicy(
                showsPersistentSidebar: false,
                showsDismissableOverlay: false
            )
        )
    }
}
