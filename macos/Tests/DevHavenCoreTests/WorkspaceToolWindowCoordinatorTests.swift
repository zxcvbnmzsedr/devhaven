import XCTest
@testable import DevHavenCore

@MainActor
final class WorkspaceToolWindowCoordinatorTests: XCTestCase {
    func testToggleShowsAndHidesSideToolWindow() {
        let harness = ToolWindowCoordinatorHarness()

        harness.coordinator.toggle(.project)
        XCTAssertEqual(harness.state.sideToolWindowState.activeKind, .project)
        XCTAssertTrue(harness.state.sideToolWindowState.isVisible)
        XCTAssertEqual(harness.state.focusedArea, .sideToolWindow(.project))
        XCTAssertEqual(harness.projectPrepareCount, 1)

        harness.coordinator.toggle(.project)
        XCTAssertFalse(harness.state.sideToolWindowState.isVisible)
        XCTAssertEqual(harness.state.focusedArea, .terminal)
    }

    func testShowBottomToolWindowClampsHeightAndFocusesBottomArea() {
        let harness = ToolWindowCoordinatorHarness(supportedKinds: [.project, .commit, .git])

        harness.coordinator.showBottom(.git)
        harness.coordinator.updateBottomHeight(80)

        XCTAssertEqual(harness.state.bottomToolWindowState.activeKind, .git)
        XCTAssertTrue(harness.state.bottomToolWindowState.isVisible)
        XCTAssertEqual(harness.state.bottomToolWindowState.height, 160)
        XCTAssertEqual(harness.state.bottomToolWindowState.lastExpandedHeight, 160)
        XCTAssertEqual(harness.state.focusedArea, .bottomToolWindow(.git))
        XCTAssertEqual(harness.gitPrepareCount, 1)
    }

    func testSyncVisibleContextsPreparesVisibleKinds() {
        let harness = ToolWindowCoordinatorHarness(supportedKinds: [.project, .commit, .git])
        harness.state.sideToolWindowState = WorkspaceSideToolWindowState(
            activeKind: .commit,
            isVisible: true
        )
        harness.state.bottomToolWindowState = WorkspaceBottomToolWindowState(
            activeKind: .git,
            isVisible: true
        )

        harness.coordinator.syncVisibleContexts()

        XCTAssertEqual(harness.commitPrepareCount, 1)
        XCTAssertEqual(harness.gitPrepareCount, 1)
    }

    func testSyncVisibleContextsHidesUnsupportedKinds() {
        let harness = ToolWindowCoordinatorHarness(supportedKinds: [.project])
        harness.state.sideToolWindowState = WorkspaceSideToolWindowState(
            activeKind: .commit,
            isVisible: true,
            width: 420,
            lastExpandedWidth: 360
        )
        harness.state.bottomToolWindowState = WorkspaceBottomToolWindowState(
            activeKind: .git,
            isVisible: true,
            height: 280,
            lastExpandedHeight: 320
        )
        harness.state.focusedArea = .bottomToolWindow(.git)

        harness.coordinator.syncVisibleContexts()

        XCTAssertFalse(harness.state.sideToolWindowState.isVisible)
        XCTAssertEqual(harness.state.sideToolWindowState.lastExpandedWidth, 420)
        XCTAssertFalse(harness.state.bottomToolWindowState.isVisible)
        XCTAssertEqual(harness.state.bottomToolWindowState.lastExpandedHeight, 280)
        XCTAssertEqual(harness.state.focusedArea, .terminal)
    }
}

@MainActor
private final class ToolWindowCoordinatorHarness {
    let state = WorkspacePresentationState()
    var supportedKinds: Set<WorkspaceToolWindowKind>
    var projectPrepareCount = 0
    var commitPrepareCount = 0
    var gitPrepareCount = 0

    lazy var coordinator = WorkspaceToolWindowCoordinator(
        presentationState: state,
        supportsKind: { [unowned self] in supportedKinds.contains($0) },
        prepareProjectTree: { [unowned self] in projectPrepareCount += 1 },
        prepareCommit: { [unowned self] in commitPrepareCount += 1 },
        prepareGit: { [unowned self] in gitPrepareCount += 1 }
    )

    init(supportedKinds: Set<WorkspaceToolWindowKind> = [.project, .commit]) {
        self.supportedKinds = supportedKinds
    }
}
