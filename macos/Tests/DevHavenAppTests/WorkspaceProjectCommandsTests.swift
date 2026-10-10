import XCTest
import DevHavenCore
@testable import DevHavenApp

@MainActor
final class WorkspaceProjectCommandsTests: XCTestCase {
    func testMenuTracksWorkspaceAndModalTransitions() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let model = NativeAppViewModel(store: LegacyCompatStore(homeDirectoryURL: home))
        let state = WorkspaceProjectCommandState(viewModel: model)

        XCTAssertFalse(state.isEnabled)
        model.enterDirectoryWorkspace(home.path)
        await waitUntil { state.isEnabled }
        XCTAssertTrue(state.isEnabled)

        model.revealSettings()
        await waitUntil { !state.isEnabled }
        XCTAssertFalse(state.isEnabled)
        model.hideSettings()
        await waitUntil { state.isEnabled }
        XCTAssertTrue(state.isEnabled)

        model.exitWorkspace()
        await waitUntil { !state.isEnabled }
        XCTAssertFalse(state.isEnabled)
    }

    func testMenuTracksShortcutChangesAfterInitialization() async {
        let model = NativeAppViewModel()
        let state = WorkspaceProjectCommandState(viewModel: model)
        XCTAssertEqual(state.shortcut, AppMenuShortcut())

        let customized = AppMenuShortcut(key: .o, usesShift: true, usesOption: true)
        model.snapshot.appState.settings.workspaceOpenProjectShortcut = customized
        await waitUntil { state.shortcut == customized }
        XCTAssertEqual(state.shortcut, customized)

        model.snapshot.appState.settings.workspaceOpenProjectShortcut = AppMenuShortcut()
        await waitUntil { state.shortcut == AppMenuShortcut() }
        XCTAssertEqual(state.shortcut, AppMenuShortcut())
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<100 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
