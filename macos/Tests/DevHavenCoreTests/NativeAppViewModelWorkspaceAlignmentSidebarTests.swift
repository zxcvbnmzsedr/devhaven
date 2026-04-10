import XCTest
@testable import DevHavenCore

@MainActor
final class NativeAppViewModelWorkspaceAlignmentSidebarTests: XCTestCase {
    func testWorkspaceAlignmentGroupSidebarExpandedPersistsAcrossReload() throws {
        let fixture = try WorkspaceAlignmentSidebarFixture.make()
        defer { fixture.cleanup() }

        let viewModel = fixture.makeViewModel()
        let group = WorkspaceAlignmentGroupDefinition(
            id: "workspace-1",
            name: "支付链路",
            targetBranch: "feature/payment"
        )
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(workspaceAlignmentGroups: [group])
        )
        try fixture.store.updateWorkspaceAlignmentGroups([group])

        viewModel.setWorkspaceAlignmentGroupSidebarExpanded(false, for: group.id)

        XCTAssertFalse(viewModel.snapshot.appState.workspaceAlignmentGroups[0].isSidebarExpanded)

        let reloadedViewModel = fixture.makeViewModel()
        reloadedViewModel.load()
        XCTAssertFalse(reloadedViewModel.snapshot.appState.workspaceAlignmentGroups[0].isSidebarExpanded)
    }

    func testSetAllWorkspaceAlignmentGroupsSidebarExpandedPersistsAcrossReload() throws {
        let fixture = try WorkspaceAlignmentSidebarFixture.make()
        defer { fixture.cleanup() }

        let viewModel = fixture.makeViewModel()
        let groups = [
            WorkspaceAlignmentGroupDefinition(
                id: "workspace-1",
                name: "支付链路",
                targetBranch: "feature/payment",
                isSidebarExpanded: true
            ),
            WorkspaceAlignmentGroupDefinition(
                id: "workspace-2",
                name: "AI套壳",
                targetBranch: "feature/ai",
                isSidebarExpanded: false
            )
        ]
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(workspaceAlignmentGroups: groups)
        )
        try fixture.store.updateWorkspaceAlignmentGroups(groups)

        viewModel.setAllWorkspaceAlignmentGroupsSidebarExpanded(false)

        XCTAssertTrue(viewModel.snapshot.appState.workspaceAlignmentGroups.allSatisfy { !$0.isSidebarExpanded })

        let reloadedViewModel = fixture.makeViewModel()
        reloadedViewModel.load()
        XCTAssertTrue(reloadedViewModel.snapshot.appState.workspaceAlignmentGroups.allSatisfy { !$0.isSidebarExpanded })
    }
}

private struct WorkspaceAlignmentSidebarFixture {
    let rootURL: URL
    let homeURL: URL
    let store: LegacyCompatStore

    static func make() throws -> WorkspaceAlignmentSidebarFixture {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("devhaven-workspace-alignment-sidebar-\(UUID().uuidString)", isDirectory: true)
        let homeURL = rootURL.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
        let store = LegacyCompatStore(homeDirectoryURL: homeURL)
        return WorkspaceAlignmentSidebarFixture(rootURL: rootURL, homeURL: homeURL, store: store)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    @MainActor
    func makeViewModel() -> NativeAppViewModel {
        NativeAppViewModel(store: store)
    }
}
