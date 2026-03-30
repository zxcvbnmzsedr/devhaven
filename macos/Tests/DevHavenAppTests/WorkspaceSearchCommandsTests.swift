import XCTest
@testable import DevHavenApp

final class WorkspaceSearchCommandsTests: XCTestCase {
    func testSearchCommandsPreferEditorWhenBothEditorAndTerminalAreEnabled() {
        XCTAssertEqual(
            workspaceSearchCommandTarget(editorEnabled: true, terminalEnabled: true),
            .editor
        )
    }

    func testSearchCommandsFallBackToTerminalWhenEditorIsDisabled() {
        XCTAssertEqual(
            workspaceSearchCommandTarget(editorEnabled: false, terminalEnabled: true),
            .terminal
        )
    }

    func testSearchCommandsDisableShortcutsWhenNeitherTargetIsEnabled() {
        XCTAssertEqual(
            workspaceSearchCommandTarget(editorEnabled: false, terminalEnabled: false),
            .none
        )
    }
}
