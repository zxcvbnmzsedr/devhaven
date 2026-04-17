import XCTest
@testable import DevHavenCore

@MainActor
final class WorkspaceEditorDocumentStoreTests: XCTestCase {
    func testUpdateTextMarksDirtyAndPromotesPreviewOnChange() {
        let harness = WorkspaceEditorDocumentStoreHarness()
        let savedFingerprint = workspaceEditorContentFingerprint("struct A {}")
        let previewTab = harness.makeTab(
            id: "editor-1",
            filePath: "/tmp/devhaven/A.swift",
            isPreview: true,
            text: "struct A {}",
            savedContentFingerprint: savedFingerprint
        )

        let result = harness.store.updateText(
            "struct A { let changed = true }",
            tabID: previewTab.id,
            in: [previewTab]
        )

        XCTAssertTrue(result.didMutate)
        XCTAssertTrue(result.tabs[0].isDirty)
        XCTAssertFalse(result.tabs[0].isPreview)
    }

    func testApplyExternalChangePreservesNonExternalMessage() {
        let harness = WorkspaceEditorDocumentStoreHarness()
        let tab = harness.makeTab(
            id: "editor-1",
            filePath: "/tmp/devhaven/A.swift",
            message: "自定义错误"
        )

        let result = harness.store.applyExternalChange(.modifiedOnDisk, tabID: tab.id, in: [tab])

        XCTAssertEqual(result.tabs[0].externalChangeState, .modifiedOnDisk)
        XCTAssertEqual(result.tabs[0].message, "自定义错误")
    }

    func testApplyExternalChangeClearsExternalMessageWhenBackInSync() {
        let harness = WorkspaceEditorDocumentStoreHarness()
        let tab = harness.makeTab(
            id: "editor-1",
            filePath: "/tmp/devhaven/A.swift",
            message: "检测到文件已被外部修改，可直接重新载入同步磁盘内容。"
        )

        let result = harness.store.applyExternalChange(.inSync, tabID: tab.id, in: [tab])

        XCTAssertEqual(result.tabs[0].externalChangeState, .inSync)
        XCTAssertNil(result.tabs[0].message)
    }

    func testApplyReloadedAndSavedDocumentRefreshesTabState() {
        let harness = WorkspaceEditorDocumentStoreHarness()
        let dirtyTab = harness.makeTab(
            id: "editor-1",
            filePath: "/tmp/devhaven/A.swift",
            text: "old",
            isDirty: true,
            isSaving: true,
            externalChangeState: .modifiedOnDisk
        )
        let document = WorkspaceEditorDocumentSnapshot(
            filePath: dirtyTab.filePath,
            kind: .text,
            text: "new",
            isEditable: true,
            message: nil,
            modificationDate: 42,
            contentFingerprint: workspaceEditorContentFingerprint("new")
        )

        let reloaded = harness.store.applyReloadedDocument(document, tabID: dirtyTab.id, in: [dirtyTab])
        XCTAssertEqual(reloaded.tabs[0].text, "new")
        XCTAssertFalse(reloaded.tabs[0].isDirty)
        XCTAssertFalse(reloaded.tabs[0].isSaving)
        XCTAssertEqual(reloaded.tabs[0].externalChangeState, .inSync)

        let begunSaving = harness.store.beginSaving(tabID: dirtyTab.id, in: reloaded.tabs)
        XCTAssertTrue(begunSaving.tabs[0].isSaving)

        let saved = harness.store.applySavedDocument(document, tabID: dirtyTab.id, in: begunSaving.tabs)
        XCTAssertFalse(saved.tabs[0].isDirty)
        XCTAssertFalse(saved.tabs[0].isSaving)
        XCTAssertEqual(saved.tabs[0].savedContentFingerprint, document.contentFingerprint)
    }

    func testSaveBlockedAndFailedMessagesAreProjectedIntoTabState() {
        let harness = WorkspaceEditorDocumentStoreHarness()
        let removedTab = harness.makeTab(
            id: "editor-removed",
            filePath: "/tmp/devhaven/A.swift",
            externalChangeState: .removedOnDisk
        )
        let blocked = harness.store.applySaveBlockedByExternalChange(tabID: removedTab.id, in: [removedTab])
        XCTAssertEqual(blocked.tabs[0].message, "磁盘上的文件已被删除，当前不能直接保存覆盖。请先重新载入或另存为新文件。")

        let failed = harness.store.applySaveFailure(
            message: "save failed",
            tabID: removedTab.id,
            in: blocked.tabs
        )
        XCTAssertFalse(failed.tabs[0].isSaving)
        XCTAssertEqual(failed.tabs[0].message, "save failed")
    }
}

@MainActor
private final class WorkspaceEditorDocumentStoreHarness {
    let store = WorkspaceEditorDocumentStore()
    let projectPath = "/tmp/devhaven-project"

    func makeTab(
        id: String,
        filePath: String,
        isPreview: Bool = false,
        text: String = "",
        isDirty: Bool = false,
        isSaving: Bool = false,
        externalChangeState: WorkspaceEditorExternalChangeState = .inSync,
        message: String? = nil,
        savedContentFingerprint: UInt64? = nil
    ) -> WorkspaceEditorTabState {
        WorkspaceEditorTabState(
            id: id,
            identity: filePath,
            projectPath: projectPath,
            filePath: filePath,
            title: URL(fileURLWithPath: filePath).lastPathComponent,
            isPreview: isPreview,
            kind: .text,
            text: text,
            isEditable: true,
            isDirty: isDirty,
            isSaving: isSaving,
            externalChangeState: externalChangeState,
            message: message,
            savedContentFingerprint: savedContentFingerprint
        )
    }
}
