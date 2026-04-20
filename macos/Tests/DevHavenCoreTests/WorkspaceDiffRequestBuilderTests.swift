import XCTest
@testable import DevHavenCore

@MainActor
final class WorkspaceDiffRequestBuilderTests: XCTestCase {
    func testCommitDiffRequestChainFallsBackToSingleWorkingTreeItemWithoutSnapshotChanges() throws {
        let builder = makeBuilder()

        let chain = builder.commitDiffRequestChain(
            repositoryPath: "/tmp/devhaven/repo",
            executionPath: "/tmp/devhaven/worktree",
            activeFilePath: "Sources/App.swift",
            activeGroup: .unstaged,
            activeStatus: .modified,
            activeOldPath: nil,
            activePreferredTitle: "App.swift",
            preferredViewerMode: .unified
        )

        XCTAssertEqual(chain.items.count, 1)
        XCTAssertEqual(chain.activeIndex, 0)
        let item = try XCTUnwrap(chain.activeItem)
        XCTAssertEqual(item.id, "working-tree|/tmp/devhaven/worktree|Sources/App.swift")
        XCTAssertEqual(item.title, "App.swift")
        XCTAssertEqual(item.preferredViewerMode, .unified)
        XCTAssertEqual(
            item.source,
            .workingTreeChange(
                repositoryPath: "/tmp/devhaven/repo",
                executionPath: "/tmp/devhaven/worktree",
                filePath: "Sources/App.swift",
                group: .unstaged,
                status: .modified,
                oldPath: nil
            )
        )
    }

    func testCommitDiffRequestChainSelectsActiveRenamedItemByFilePathAndOldPath() throws {
        let builder = makeBuilder(
            commitChanges: [
                WorkspaceCommitChange(
                    path: "Sources/Before.swift",
                    status: .modified,
                    group: .unstaged,
                    isIncludedByDefault: false
                ),
                WorkspaceCommitChange(
                    path: "Sources/After.swift",
                    oldPath: "Sources/Legacy.swift",
                    status: .renamed,
                    group: .staged,
                    isIncludedByDefault: true
                ),
            ]
        )

        let chain = builder.commitDiffRequestChain(
            repositoryPath: "/tmp/devhaven/repo",
            executionPath: "/tmp/devhaven/worktree",
            activeFilePath: "Sources/After.swift",
            activeGroup: .staged,
            activeStatus: .renamed,
            activeOldPath: "Sources/Legacy.swift",
            activePreferredTitle: "After.swift",
            preferredViewerMode: .sideBySide
        )

        XCTAssertEqual(chain.items.count, 2)
        XCTAssertEqual(chain.activeIndex, 1)
        XCTAssertEqual(chain.items[0].title, "Changes: Before.swift")
        let activeItem = chain.items[1]
        XCTAssertEqual(activeItem.title, "After.swift")
        XCTAssertEqual(activeItem.id, "working-tree|/tmp/devhaven/worktree|Sources/After.swift")
        if case let .workingTreeChange(repositoryPath, executionPath, filePath, group, status, oldPath) = activeItem.source {
            XCTAssertEqual(repositoryPath, "/tmp/devhaven/repo")
            XCTAssertEqual(executionPath, "/tmp/devhaven/worktree")
            XCTAssertEqual(filePath, "Sources/After.swift")
            XCTAssertEqual(group, .staged)
            XCTAssertEqual(status, .renamed)
            XCTAssertEqual(oldPath, "Sources/Legacy.swift")
        } else {
            XCTFail("expected working tree diff source")
        }
    }

    func testGitLogDiffRequestChainBuildsMultiFileChainAndPaneMetadataFromSelectedDetail() throws {
        let detail = WorkspaceGitCommitDetail(
            hash: "abcdef123456",
            shortHash: "abcdef1",
            parentHashes: ["fedcba654321"],
            authorName: "DevHaven",
            authorEmail: "devhaven@example.com",
            authorTimestamp: 1_713_528_000,
            subject: "Refactor diff builder",
            body: nil,
            decorations: nil,
            changedFiles: [
                WorkspaceGitCommitFileChange(path: "Sources/First.swift", status: .modified),
                WorkspaceGitCommitFileChange(
                    path: "Sources/Renamed.swift",
                    oldPath: "Sources/Legacy.swift",
                    status: .renamed
                ),
            ]
        )
        let builder = makeBuilder(selectedGitCommitDetail: detail)

        let chain = builder.gitLogDiffRequestChain(
            repositoryPath: "/tmp/devhaven/repo",
            commitHash: "abcdef123456",
            activeFilePath: "Sources/Renamed.swift",
            activePreferredTitle: "Renamed.swift",
            preferredViewerMode: .sideBySide
        )

        XCTAssertEqual(chain.items.count, 2)
        XCTAssertEqual(chain.activeIndex, 1)
        XCTAssertEqual(chain.items[0].title, "Commit: First.swift")
        let activeItem = chain.items[1]
        XCTAssertEqual(activeItem.id, "git-log|/tmp/devhaven/repo|abcdef123456|Sources/Renamed.swift")
        XCTAssertEqual(activeItem.title, "Renamed.swift")
        XCTAssertEqual(activeItem.preferredViewerMode, .sideBySide)
        XCTAssertEqual(activeItem.paneMetadataSeeds.count, 2)

        let leftSeed = activeItem.paneMetadataSeeds[0]
        XCTAssertEqual(leftSeed.role, .left)
        XCTAssertEqual(leftSeed.title, "Before")
        XCTAssertEqual(leftSeed.path, "Sources/Legacy.swift")
        XCTAssertEqual(leftSeed.revision, "fedcba654321")
        XCTAssertEqual(leftSeed.hash, "fedcba654321")
        XCTAssertEqual(leftSeed.author, "DevHaven")
        XCTAssertNotNil(leftSeed.timestamp)

        let rightSeed = activeItem.paneMetadataSeeds[1]
        XCTAssertEqual(rightSeed.role, .right)
        XCTAssertEqual(rightSeed.title, "After")
        XCTAssertEqual(rightSeed.path, "Sources/Renamed.swift")
        XCTAssertEqual(rightSeed.oldPath, "Sources/Legacy.swift")
        XCTAssertEqual(rightSeed.revision, "abcdef1")
        XCTAssertEqual(rightSeed.hash, "abcdef123456")
        XCTAssertEqual(rightSeed.author, "DevHaven")
        XCTAssertNotNil(rightSeed.timestamp)
        XCTAssertEqual(
            rightSeed.copyPayloads,
            [
                WorkspaceDiffPaneCopyPayload(
                    id: "commit-hash",
                    label: "提交哈希",
                    value: "abcdef123456"
                )
            ]
        )
    }

    func testGitLogDiffRequestChainFallsBackToSingleItemWhenSelectedDetailDoesNotMatchCommit() throws {
        let detail = WorkspaceGitCommitDetail(
            hash: "other-commit",
            shortHash: "other",
            parentHashes: ["parent"],
            authorName: "Other",
            authorEmail: "other@example.com",
            authorTimestamp: 1_713_528_000,
            subject: "Other commit",
            body: nil,
            decorations: nil,
            changedFiles: [
                WorkspaceGitCommitFileChange(path: "Sources/Ignored.swift", status: .modified)
            ]
        )
        let builder = makeBuilder(selectedGitCommitDetail: detail)

        let chain = builder.gitLogDiffRequestChain(
            repositoryPath: "/tmp/devhaven/repo",
            commitHash: "target-commit",
            activeFilePath: "Sources/Only.swift",
            activePreferredTitle: "Only.swift",
            preferredViewerMode: .unified
        )

        XCTAssertEqual(chain.items.count, 1)
        XCTAssertEqual(chain.activeIndex, 0)
        let item = try XCTUnwrap(chain.activeItem)
        XCTAssertEqual(item.id, "git-log|/tmp/devhaven/repo|target-commit|Sources/Only.swift")
        XCTAssertEqual(item.title, "Only.swift")
        XCTAssertEqual(item.preferredViewerMode, .unified)
        XCTAssertEqual(item.paneMetadataSeeds.count, 2)
        XCTAssertEqual(item.paneMetadataSeeds[0].role, .left)
        XCTAssertEqual(item.paneMetadataSeeds[0].title, "Before")
        XCTAssertEqual(item.paneMetadataSeeds[0].path, "Sources/Only.swift")
        XCTAssertNil(item.paneMetadataSeeds[0].revision)
        XCTAssertEqual(item.paneMetadataSeeds[1].role, .right)
        XCTAssertEqual(item.paneMetadataSeeds[1].title, "After")
        XCTAssertEqual(item.paneMetadataSeeds[1].path, "Sources/Only.swift")
        XCTAssertEqual(item.paneMetadataSeeds[1].revision, "target-commit")
        XCTAssertEqual(item.paneMetadataSeeds[1].hash, "target-commit")
        XCTAssertEqual(
            item.source,
            .gitLogCommitFile(
                repositoryPath: "/tmp/devhaven/repo",
                commitHash: "target-commit",
                filePath: "Sources/Only.swift"
            )
        )
    }

    private func makeBuilder(
        commitChanges: [WorkspaceCommitChange]? = nil,
        selectedGitCommitDetail: WorkspaceGitCommitDetail? = nil
    ) -> WorkspaceDiffRequestBuilder {
        WorkspaceDiffRequestBuilder(
            commitChanges: { commitChanges },
            selectedGitCommitDetail: { selectedGitCommitDetail }
        )
    }
}
