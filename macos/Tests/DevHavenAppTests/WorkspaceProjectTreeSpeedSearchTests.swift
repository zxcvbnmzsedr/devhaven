import XCTest
@testable import DevHavenApp
@testable import DevHavenCore

final class WorkspaceProjectTreeSpeedSearchTests: XCTestCase {
    func testFilteringKeepsMatchingAncestorChainAndPrunesUnmatchedSiblings() {
        let rootNodes = [
            WorkspaceProjectTreeDisplayNode(
                path: "/repo/src",
                parentPath: nil,
                name: "src",
                kind: .directory,
                children: [
                    WorkspaceProjectTreeDisplayNode(
                        path: "/repo/src/App.swift",
                        parentPath: "/repo/src",
                        name: "App.swift",
                        kind: .file
                    ),
                    WorkspaceProjectTreeDisplayNode(
                        path: "/repo/src/Feature",
                        parentPath: "/repo/src",
                        name: "Feature",
                        kind: .directory,
                        children: [
                            WorkspaceProjectTreeDisplayNode(
                                path: "/repo/src/Feature/UserService.swift",
                                parentPath: "/repo/src/Feature",
                                name: "UserService.swift",
                                kind: .file
                            )
                        ]
                    ),
                ]
            )
        ]

        let filtered = workspaceProjectTreeFilteredNodes(rootNodes, query: "user")

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.name, "src")
        XCTAssertEqual(filtered.first?.children.map(\.name), ["Feature"])
        XCTAssertEqual(filtered.first?.children.first?.children.map(\.name), ["UserService.swift"])
    }

    func testFilteringMatchesCompactedJavaPackageNames() {
        let node = WorkspaceProjectTreeDisplayNode(
            path: "/repo/src/main/java/com/example/service",
            parentPath: "/repo/src/main/java",
            name: "com.example.service",
            kind: .directory,
            compactedDirectoryPaths: [
                "/repo/src/main/java/com",
                "/repo/src/main/java/com/example",
                "/repo/src/main/java/com/example/service",
            ]
        )

        XCTAssertTrue(workspaceProjectTreeNodeMatchesSpeedSearch(node, query: "example"))
        XCTAssertTrue(workspaceProjectTreeNodeMatchesSpeedSearch(node, query: "service"))
        XCTAssertFalse(workspaceProjectTreeNodeMatchesSpeedSearch(node, query: "controller"))
    }

    func testKeyCaptureDoesNotStealTypingFromTextInputs() {
        let action = workspaceProjectTreeKeyCaptureAction(
            isEnabled: true,
            keyCode: 0,
            charactersIgnoringModifiers: "a",
            modifierFlags: [],
            firstResponderIsTextInput: true
        )

        XCTAssertNil(action)
    }

    func testKeyCaptureMapsPlainTypingAndControlKeysIntoSpeedSearchActions() {
        XCTAssertEqual(
            workspaceProjectTreeKeyCaptureAction(
                isEnabled: true,
                keyCode: 0,
                charactersIgnoringModifiers: "a",
                modifierFlags: [],
                firstResponderIsTextInput: false
            ),
            .input("a")
        )
        XCTAssertEqual(
            workspaceProjectTreeKeyCaptureAction(
                isEnabled: true,
                keyCode: 51,
                charactersIgnoringModifiers: "",
                modifierFlags: [],
                firstResponderIsTextInput: false
            ),
            .backspace
        )
        XCTAssertEqual(
            workspaceProjectTreeKeyCaptureAction(
                isEnabled: true,
                keyCode: 53,
                charactersIgnoringModifiers: "",
                modifierFlags: [],
                firstResponderIsTextInput: false
            ),
            .clear
        )
    }
}
