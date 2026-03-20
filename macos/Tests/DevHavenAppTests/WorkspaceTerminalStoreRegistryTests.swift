import XCTest
@testable import DevHavenApp
@testable import DevHavenCore

@MainActor
final class WorkspaceTerminalStoreRegistryTests: XCTestCase {
    func testRegistryReusesStoreForSameProjectPath() {
        let registry = WorkspaceTerminalStoreRegistry()

        let first = registry.store(for: "/tmp/alpha")
        let second = registry.store(for: "/tmp/alpha")

        XCTAssertIdentical(first, second)
        XCTAssertEqual(registry.storeCount, 1)
    }

    func testRegistryReleasesStoresForRemovedProjectPathsDuringSync() {
        let registry = WorkspaceTerminalStoreRegistry()
        let alpha = registry.store(for: "/tmp/alpha")
        _ = registry.store(for: "/tmp/beta")

        registry.syncRetainedProjectPaths(["/tmp/beta"])

        XCTAssertEqual(registry.storeCount, 1)
        let recreated = registry.store(for: "/tmp/alpha")
        XCTAssertFalse(alpha === recreated)
    }

    func testWarmActiveWorkspaceSessionOnlyWarmsSelectedPaneForActiveProject() {
        let registry = WorkspaceTerminalStoreRegistry()
        let alpha = makeSession(projectPath: "/tmp/alpha")
        let beta = makeSession(projectPath: "/tmp/beta", split: true)
        let alphaStore = registry.store(for: alpha.projectPath)
        let betaStore = registry.store(for: beta.projectPath)

        registry.warmActiveWorkspaceSession(
            sessions: [alpha, beta],
            activeProjectPath: beta.projectPath
        )

        XCTAssertEqual(alphaStore.modelCount, 0)
        XCTAssertEqual(betaStore.modelCount, 1)
    }

    private func makeSession(projectPath: String, split: Bool = false) -> OpenWorkspaceSessionState {
        let controller = GhosttyWorkspaceController(projectPath: projectPath)
        if split {
            _ = controller.splitFocusedPane(direction: .right)
        }
        return OpenWorkspaceSessionState(projectPath: projectPath, controller: controller)
    }
}
