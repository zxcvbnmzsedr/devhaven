import XCTest
import DevHavenCore
@testable import DevHavenApp

final class WorkspaceProjectPickerSearchTests: XCTestCase {
    func testWorkspaceProjectPickerMatchesSearchIncludesNotesSummary() {
        let project = makeProject(
            name: "Payments",
            path: "/tmp/payments",
            tags: [],
            notesSummary: "供应商报价聚合与回调排障"
        )

        XCTAssertTrue(workspaceProjectPickerMatchesSearch(project, query: "报价聚合"))
    }

    func testWorkspaceProjectPickerMatchesSearchIncludesTags() {
        let project = makeProject(
            name: "Payments",
            path: "/tmp/payments",
            tags: ["core", "workspace"],
            notesSummary: nil
        )

        XCTAssertTrue(workspaceProjectPickerMatchesSearch(project, query: "workspace"))
    }

    func testWorkspaceProjectPickerMatchesSearchReturnsTrueForBlankQuery() {
        let project = makeProject(
            name: "Payments",
            path: "/tmp/payments",
            tags: [],
            notesSummary: nil
        )

        XCTAssertTrue(workspaceProjectPickerMatchesSearch(project, query: "   "))
    }

    private func makeProject(
        name: String,
        path: String,
        tags: [String],
        notesSummary: String?
    ) -> Project {
        Project(
            id: path,
            name: name,
            path: path,
            tags: tags,
            runConfigurations: [],
            worktrees: [],
            mtime: 0,
            size: 0,
            checksum: "",
            isGitRepository: true,
            gitCommits: 0,
            gitLastCommit: 0,
            gitLastCommitMessage: nil,
            gitDaily: nil,
            notesSummary: notesSummary,
            created: 0,
            checked: 0
        )
    }
}
