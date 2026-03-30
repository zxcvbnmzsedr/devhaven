import XCTest
import DevHavenCore
@testable import DevHavenApp

final class WorkspaceTabBarViewSemanticsTests: XCTestCase {
    func testPinnedEditorTabUsesPinAccessory() {
        let semantics = WorkspaceTabChipSemantics.resolve(
            for: WorkspacePresentedTabItem(
                id: "editor-1",
                title: "Pinned.swift",
                selection: .editor("editor-1"),
                isSelected: false,
                isPinned: true
            )
        )

        XCTAssertEqual(semantics.leadingStatusSystemImage, "pin.fill")
        XCTAssertNil(semantics.badgeTitle)
        XCTAssertFalse(semantics.usesItalicTitle)
        XCTAssertEqual(semantics.titleOpacity, 1)
    }

    func testPreviewEditorTabUsesPreviewBadgeAndItalicTitle() {
        let semantics = WorkspaceTabChipSemantics.resolve(
            for: WorkspacePresentedTabItem(
                id: "editor-2",
                title: "Preview.swift",
                selection: .editor("editor-2"),
                isSelected: false,
                isPreview: true
            )
        )

        XCTAssertNil(semantics.leadingStatusSystemImage)
        XCTAssertEqual(semantics.badgeTitle, "预览")
        XCTAssertTrue(semantics.usesItalicTitle)
        XCTAssertLessThan(semantics.titleOpacity, 1)
    }
}
