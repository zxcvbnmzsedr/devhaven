import XCTest
@testable import DevHavenCore

@MainActor
final class WorkspaceEditorTabStoreTests: XCTestCase {
    func testPreviewOpenReusesSingleUnpinnedPreviewTab() {
        let harness = WorkspaceEditorTabStoreHarness()
        let firstPreview = harness.makeTab(
            id: "editor-preview",
            filePath: "/tmp/devhaven/First.swift",
            isPreview: true
        )

        let result = harness.store.openNewTab(
            projectPath: harness.projectPath,
            filePath: "/tmp/devhaven/Second.swift",
            document: harness.makeDocument(filePath: "/tmp/devhaven/Second.swift"),
            openingPolicy: .preview,
            in: [firstPreview]
        )

        XCTAssertEqual(result.tabs.count, 1)
        XCTAssertEqual(result.openedTabID, firstPreview.id)
        XCTAssertTrue(result.resetRuntimeSession)
        XCTAssertTrue(result.assignToActiveGroup)
        XCTAssertEqual(result.tabs.first?.id, firstPreview.id)
        XCTAssertEqual(result.tabs.first?.filePath, "/tmp/devhaven/Second.swift")
        XCTAssertTrue(result.tabs.first?.isPreview == true)
    }

    func testPinnedTabIsNotReusedByPreview() {
        let harness = WorkspaceEditorTabStoreHarness()
        let pinned = harness.makeTab(
            id: "editor-pinned",
            filePath: "/tmp/devhaven/Pinned.swift",
            isPinned: true
        )

        let result = harness.store.openNewTab(
            projectPath: harness.projectPath,
            filePath: "/tmp/devhaven/Second.swift",
            document: harness.makeDocument(filePath: "/tmp/devhaven/Second.swift"),
            openingPolicy: .preview,
            in: [pinned]
        )

        XCTAssertEqual(result.tabs.count, 2)
        XCTAssertEqual(result.openedTabID, "generated-1")
        XCTAssertFalse(result.resetRuntimeSession)
        XCTAssertEqual(result.tabs.first?.id, pinned.id)
        XCTAssertEqual(result.tabs.last?.id, "generated-1")
        XCTAssertTrue(result.tabs.last?.isPreview == true)
    }

    func testRegularReopenPromotesExistingPreviewWithoutChangingID() throws {
        let harness = WorkspaceEditorTabStoreHarness()
        let preview = harness.makeTab(
            id: "editor-preview",
            filePath: "/tmp/devhaven/File.swift",
            isPreview: true
        )

        let result = try XCTUnwrap(
            harness.store.reopenExistingTab(
                filePath: "/tmp/devhaven/File.swift",
                openingPolicy: .regular,
                in: [preview]
            )
        )

        XCTAssertEqual(result.openedTabID, preview.id)
        XCTAssertFalse(result.resetRuntimeSession)
        XCTAssertFalse(result.assignToActiveGroup)
        XCTAssertFalse(result.tabs.first?.isPreview == true)
        XCTAssertFalse(result.tabs.first?.isPinned == true)
    }

    func testPinnedReopenPromotesExistingPreviewAndKeepsPinnedBlockOrdering() throws {
        let harness = WorkspaceEditorTabStoreHarness()
        let regular = harness.makeTab(id: "editor-regular", filePath: "/tmp/devhaven/Regular.swift")
        let preview = harness.makeTab(
            id: "editor-preview",
            filePath: "/tmp/devhaven/Preview.swift",
            isPreview: true
        )

        let result = try XCTUnwrap(
            harness.store.reopenExistingTab(
                filePath: "/tmp/devhaven/Preview.swift",
                openingPolicy: .pinned,
                in: [regular, preview]
            )
        )

        XCTAssertEqual(result.openedTabID, preview.id)
        XCTAssertEqual(result.tabs.map(\.id), [preview.id, regular.id])
        XCTAssertTrue(result.tabs.first?.isPinned == true)
        XCTAssertFalse(result.tabs.first?.isPreview == true)
    }

    func testPromotePreviewToRegularMutatesOnlyPreviewTabs() {
        let harness = WorkspaceEditorTabStoreHarness()
        let preview = harness.makeTab(
            id: "editor-preview",
            filePath: "/tmp/devhaven/Preview.swift",
            isPreview: true
        )

        let promoted = harness.store.promotePreviewTabToRegular(preview.id, in: [preview])
        XCTAssertTrue(promoted.didMutate)
        XCTAssertFalse(promoted.tabs.first?.isPreview == true)

        let noop = harness.store.promotePreviewTabToRegular(preview.id, in: promoted.tabs)
        XCTAssertFalse(noop.didMutate)
        XCTAssertEqual(noop.tabs, promoted.tabs)
    }

    func testUnpinReinsertsTabAtUnpinnedBoundary() {
        let harness = WorkspaceEditorTabStoreHarness()
        let pinnedA = harness.makeTab(id: "editor-pinned-a", filePath: "/tmp/devhaven/A.swift", isPinned: true)
        let pinnedB = harness.makeTab(id: "editor-pinned-b", filePath: "/tmp/devhaven/B.swift", isPinned: true)
        let regular = harness.makeTab(id: "editor-regular", filePath: "/tmp/devhaven/C.swift")

        let result = harness.store.setTabPinned(false, tabID: pinnedB.id, in: [pinnedA, pinnedB, regular])

        XCTAssertTrue(result.didMutate)
        XCTAssertEqual(result.tabs.map(\.id), [pinnedA.id, pinnedB.id, regular.id])
        XCTAssertTrue(result.tabs[0].isPinned)
        XCTAssertFalse(result.tabs[1].isPinned)
        XCTAssertFalse(result.tabs[1].isPreview)
    }
}

@MainActor
private final class WorkspaceEditorTabStoreHarness {
    let projectPath = "/tmp/devhaven-project"
    private var nextGeneratedID = 0

    lazy var store = WorkspaceEditorTabStore(
        normalizePath: { $0 },
        makeTabID: { [unowned self] in
            nextGeneratedID += 1
            return "generated-\(nextGeneratedID)"
        }
    )

    func makeDocument(filePath: String) -> WorkspaceEditorDocumentSnapshot {
        WorkspaceEditorDocumentSnapshot(
            filePath: filePath,
            kind: .text,
            text: "// \(URL(fileURLWithPath: filePath).lastPathComponent)",
            isEditable: true,
            contentFingerprint: workspaceEditorContentFingerprint(filePath)
        )
    }

    func makeTab(
        id: String,
        filePath: String,
        isPinned: Bool = false,
        isPreview: Bool = false
    ) -> WorkspaceEditorTabState {
        WorkspaceEditorTabState(
            id: id,
            identity: filePath,
            projectPath: projectPath,
            filePath: filePath,
            title: URL(fileURLWithPath: filePath).lastPathComponent,
            isPinned: isPinned,
            isPreview: isPreview,
            kind: .text,
            text: "",
            isEditable: true
        )
    }
}
