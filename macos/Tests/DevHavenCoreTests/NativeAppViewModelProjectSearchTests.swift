import XCTest
@testable import DevHavenCore

@MainActor
final class NativeAppViewModelProjectSearchTests: XCTestCase {
    func testFilteredProjectsMatchesNotesSummary() {
        let notesProject = makeProject(
            id: "notes-project",
            name: "Payments",
            path: "/tmp/payments",
            isGitRepository: true,
            notesSummary: "供应商报价聚合与回调排障"
        )
        let otherProject = makeProject(
            id: "other-project",
            name: "Console",
            path: "/tmp/console",
            isGitRepository: true,
            notesSummary: "终端标题与布局"
        )

        let viewModel = NativeAppViewModel()
        viewModel.snapshot = NativeAppSnapshot(projects: [notesProject, otherProject])
        viewModel.searchQuery = "报价聚合"

        XCTAssertEqual(viewModel.filteredProjects.map(\.id), [notesProject.id])
    }

    func testFilteredProjectsStillRespectsGitFilterWhenQueryMatchesNotesSummary() {
        let nonGitProject = makeProject(
            id: "notes-only-project",
            name: "Notes",
            path: "/tmp/notes",
            isGitRepository: false,
            notesSummary: "可通过备注关键字命中"
        )
        let gitProject = makeProject(
            id: "git-project",
            name: "Workspace",
            path: "/tmp/workspace",
            isGitRepository: true,
            notesSummary: "另一个备注"
        )

        let viewModel = NativeAppViewModel()
        viewModel.snapshot = NativeAppSnapshot(projects: [nonGitProject, gitProject])
        viewModel.updateGitFilter(.gitOnly)
        viewModel.searchQuery = "备注关键字"

        XCTAssertTrue(viewModel.filteredProjects.isEmpty)
    }

    private func makeProject(
        id: String,
        name: String,
        path: String,
        isGitRepository: Bool,
        notesSummary: String?
    ) -> Project {
        Project(
            id: id,
            name: name,
            path: path,
            tags: [],
            runConfigurations: [],
            worktrees: [],
            mtime: 0,
            size: 0,
            checksum: "",
            isGitRepository: isGitRepository,
            gitCommits: isGitRepository ? 1 : 0,
            gitLastCommit: 0,
            gitLastCommitMessage: nil,
            gitDaily: nil,
            notesSummary: notesSummary,
            created: 0,
            checked: 0
        )
    }
}
