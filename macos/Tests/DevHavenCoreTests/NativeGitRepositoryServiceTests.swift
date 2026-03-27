import XCTest
@testable import DevHavenCore

final class NativeGitRepositoryServiceTests: XCTestCase {
    func testLoadLogSnapshotReturnsGraphPrefixAndCommitMetadata() throws {
        let fixture = try GitRepositoryFixture()
        let repositoryURL = try fixture.createRepository(named: "git-log")
        try fixture.createCommit(in: repositoryURL, message: "feat: second", fileName: "README.md", content: "hello\nsecond\n")
        try fixture.run(["git", "tag", "v1.0.0"], at: repositoryURL)

        let service = NativeGitRepositoryService()

        let snapshot = try service.loadLogSnapshot(at: repositoryURL.path())

        XCTAssertEqual(snapshot.commits.count, 2)
        XCTAssertEqual(snapshot.commits.first?.subject, "feat: second")
        XCTAssertEqual(snapshot.commits.first?.authorName, "DevHaven")
        XCTAssertEqual(snapshot.commits.first?.graphPrefix.trimmingCharacters(in: .whitespaces), "*")
        XCTAssertEqual(snapshot.refs.localBranches.first?.name, "main")
        XCTAssertEqual(snapshot.refs.tags.first?.name, "v1.0.0")
    }

    func testLoadCommitDetailReturnsFilesAndDiff() throws {
        let fixture = try GitRepositoryFixture()
        let repositoryURL = try fixture.createRepository(named: "git-detail")
        let commitHash = try fixture.createCommit(
            in: repositoryURL,
            message: "feat: update readme",
            fileName: "README.md",
            content: "hello\nupdated\n"
        )

        let service = NativeGitRepositoryService()

        let detail = try service.loadCommitDetail(at: repositoryURL.path(), commitHash: commitHash)

        XCTAssertEqual(detail.hash, commitHash)
        XCTAssertEqual(detail.subject, "feat: update readme")
        XCTAssertEqual(detail.files.count, 1)
        XCTAssertEqual(detail.files.first?.path, "README.md")
        XCTAssertEqual(detail.files.first?.status, .modified)
        XCTAssertTrue(detail.diff.contains("+updated"))
    }

    func testLoadChangesSnapshotSeparatesStagedUnstagedAndUntracked() throws {
        let fixture = try GitRepositoryFixture()
        let repositoryURL = try fixture.createRepository(named: "git-status")

        let stagedURL = repositoryURL.appending(path: "staged.txt")
        try "stage me\n".write(to: stagedURL, atomically: true, encoding: .utf8)
        try fixture.run(["git", "add", "staged.txt"], at: repositoryURL)

        let unstagedURL = repositoryURL.appending(path: "README.md")
        try "hello\nchanged\n".write(to: unstagedURL, atomically: true, encoding: .utf8)

        let untrackedURL = repositoryURL.appending(path: "untracked.txt")
        try "new\n".write(to: untrackedURL, atomically: true, encoding: .utf8)

        let service = NativeGitRepositoryService()

        let snapshot = try service.loadChanges(at: repositoryURL.path())

        XCTAssertEqual(snapshot.staged.map(\.path), ["staged.txt"])
        XCTAssertEqual(snapshot.unstaged.map(\.path), ["README.md"])
        XCTAssertEqual(snapshot.untracked.map(\.path), ["untracked.txt"])
        XCTAssertEqual(snapshot.aheadCount, 0)
        XCTAssertEqual(snapshot.behindCount, 0)
    }

    func testLoadChangesSnapshotExpandsUntrackedDirectoriesIntoFilesAndSkipsEmptyDirectories() throws {
        let fixture = try GitRepositoryFixture()
        let repositoryURL = try fixture.createRepository(named: "git-untracked-directory")

        try FileManager.default.createDirectory(
            at: repositoryURL.appending(path: "empty-dir", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: repositoryURL.appending(path: "filled-dir", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        try "nested\n".write(
            to: repositoryURL.appending(path: "filled-dir/file.txt"),
            atomically: true,
            encoding: .utf8
        )

        let service = NativeGitRepositoryService()
        let snapshot = try service.loadChanges(at: repositoryURL.path())

        XCTAssertEqual(snapshot.untracked.map(\.path), ["filled-dir/file.txt"])
        XCTAssertFalse(snapshot.untracked.contains(where: { $0.path == "empty-dir/" || $0.path == "empty-dir" }))
        XCTAssertFalse(snapshot.untracked.contains(where: { $0.path == "filled-dir/" }))
    }

    func testResolveGitDirSupportsLinkedWorktreeGitFile() throws {
        let fixture = try GitRepositoryFixture()
        let repositoryURL = try fixture.createRepository(named: "git-worktree")
        let worktreeURL = fixture.homeURL
            .appending(path: "linked", directoryHint: .isDirectory)

        try fixture.run(["git", "worktree", "add", worktreeURL.path(), "-b", "feature/demo"], at: repositoryURL)

        let service = NativeGitRepositoryService()

        let gitDir = try service.resolveGitDir(at: worktreeURL.path())

        XCTAssertNotEqual(gitDir, worktreeURL.appending(path: ".git").path())
        XCTAssertTrue(FileManager.default.fileExists(atPath: gitDir))
        XCTAssertTrue(gitDir.contains("/worktrees/"))
    }

    func testLoadChangesSnapshotHandlesDetachedHeadAndMissingUpstream() throws {
        let fixture = try GitRepositoryFixture()
        let repositoryURL = try fixture.createRepository(named: "git-detached")
        let commitHash = try fixture.gitOutput(["git", "rev-parse", "HEAD"], at: repositoryURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try fixture.run(["git", "checkout", commitHash], at: repositoryURL)

        let service = NativeGitRepositoryService()

        let snapshot = try service.loadChanges(at: repositoryURL.path())

        XCTAssertEqual(snapshot.headName, "HEAD")
        XCTAssertNil(snapshot.upstreamName)
        XCTAssertEqual(snapshot.aheadCount, 0)
        XCTAssertEqual(snapshot.behindCount, 0)
    }

    func testLoadLogSnapshotUsesDefaultLimit300() throws {
        let fixture = try GitRepositoryFixture()
        let repositoryURL = try fixture.createRepository(named: "git-limit")
        for index in 1...304 {
            try fixture.createEmptyCommit(in: repositoryURL, message: "commit \(index)")
        }

        let service = NativeGitRepositoryService()

        let snapshot = try service.loadLogSnapshot(at: repositoryURL.path())

        XCTAssertEqual(snapshot.commits.count, 300)
        XCTAssertEqual(snapshot.commits.first?.subject, "commit 304")
    }

    func testLoadLogSnapshotUsesDateOrderLikeIdeaNormalSort() throws {
        let fixture = try GitRepositoryFixture()
        let repositoryURL = try fixture.createRepository(named: "git-date-order")

        _ = try fixture.createCommit(
            in: repositoryURL,
            message: "fix: main base",
            fileName: "Base.swift",
            content: "base\n",
            environment: fixture.gitIdentityEnvironment(
                authorDate: "2026-03-24T09:00:00Z",
                committerDate: "2026-03-24T09:00:00Z"
            )
        )

        try fixture.run(["git", "checkout", "-b", "feature/38"], at: repositoryURL)
        _ = try fixture.createCommit(
            in: repositoryURL,
            message: "feat: branch one",
            fileName: "FeatureOne.swift",
            content: "one\n",
            environment: fixture.gitIdentityEnvironment(
                authorDate: "2026-03-24T10:00:00Z",
                committerDate: "2026-03-24T10:00:00Z"
            )
        )
        _ = try fixture.createCommit(
            in: repositoryURL,
            message: "feat: branch two",
            fileName: "FeatureTwo.swift",
            content: "two\n",
            environment: fixture.gitIdentityEnvironment(
                authorDate: "2026-03-24T11:00:00Z",
                committerDate: "2026-03-24T11:00:00Z"
            )
        )

        try fixture.run(["git", "checkout", "main"], at: repositoryURL)
        try fixture.run(["git", "checkout", "-b", "focus"], at: repositoryURL)
        _ = try fixture.createCommit(
            in: repositoryURL,
            message: "feat: focus shortcut",
            fileName: "Focus.swift",
            content: "focus\n",
            environment: fixture.gitIdentityEnvironment(
                authorDate: "2026-03-24T12:00:00Z",
                committerDate: "2026-03-24T12:00:00Z"
            )
        )

        try fixture.run(["git", "checkout", "main"], at: repositoryURL)
        try fixture.run(
            ["git", "merge", "--no-ff", "focus", "-m", "Merge branch 'focus'"],
            at: repositoryURL,
            environment: fixture.gitIdentityEnvironment(
                authorDate: "2026-03-24T13:00:00Z",
                committerDate: "2026-03-24T13:00:00Z"
            )
        )
        try fixture.run(
            ["git", "merge", "--no-ff", "feature/38", "-m", "Merge branch 'feature/38'"],
            at: repositoryURL,
            environment: fixture.gitIdentityEnvironment(
                authorDate: "2026-03-24T14:00:00Z",
                committerDate: "2026-03-24T14:00:00Z"
            )
        )
        _ = try fixture.createCommit(
            in: repositoryURL,
            message: "fix: after merge",
            fileName: "AfterMerge.swift",
            content: "done\n",
            environment: fixture.gitIdentityEnvironment(
                authorDate: "2026-03-24T15:00:00Z",
                committerDate: "2026-03-24T15:00:00Z"
            )
        )

        let service = NativeGitRepositoryService()

        let snapshot = try service.loadLogSnapshot(at: repositoryURL.path())
        let expectedSubjects = try fixture.graphLogSubjects(
            at: repositoryURL,
            additionalArguments: ["--date-order"]
        )

        XCTAssertEqual(
            snapshot.commits.map(\.subject),
            expectedSubjects,
            "IDEA Normal/Off 排序是“按拓扑并按日期”，不应继续把整条被 merge 的 incoming branch 直接排在 merge commit 下方"
        )
    }

    func testLoadLogSnapshotSupportsAuthorAndPathFilters() throws {
        let fixture = try GitRepositoryFixture()
        let repositoryURL = try fixture.createRepository(named: "git-log-filters")

        _ = try fixture.createCommit(
            in: repositoryURL,
            message: "feat: server only",
            fileName: "Sources/Server/App.swift",
            content: "server\n",
            environment: fixture.gitIdentityEnvironment(name: "Alice", email: "alice@example.com")
        )
        _ = try fixture.createCommit(
            in: repositoryURL,
            message: "feat: tests only",
            fileName: "Tests/AppTests/AppTests.swift",
            content: "tests\n",
            environment: fixture.gitIdentityEnvironment(name: "Bob", email: "bob@example.com")
        )

        let service = NativeGitRepositoryService()

        let filtered = try service.loadLogSnapshot(
            at: repositoryURL.path(),
            query: WorkspaceGitLogQuery(author: "Alice", path: "Sources/Server")
        )

        XCTAssertEqual(filtered.commits.count, 1)
        XCTAssertEqual(filtered.commits.first?.authorName, "Alice")
        XCTAssertEqual(filtered.commits.first?.subject, "feat: server only")
    }

    func testLoadLogSnapshotSupportsSinceFilter() throws {
        let fixture = try GitRepositoryFixture()
        let repositoryURL = try fixture.createRepository(named: "git-log-since")

        _ = try fixture.createCommit(
            in: repositoryURL,
            message: "feat: old commit",
            fileName: "Old.swift",
            content: "old\n",
            environment: fixture.gitIdentityEnvironment(
                name: "DevHaven",
                email: "devhaven@example.com",
                authorDate: "2020-01-01T00:00:00Z",
                committerDate: "2020-01-01T00:00:00Z"
            )
        )
        _ = try fixture.createCommit(
            in: repositoryURL,
            message: "feat: fresh commit",
            fileName: "Fresh.swift",
            content: "fresh\n",
            environment: fixture.gitIdentityEnvironment(
                name: "DevHaven",
                email: "devhaven@example.com",
                authorDate: "2030-01-01T00:00:00Z",
                committerDate: "2030-01-01T00:00:00Z"
            )
        )

        let service = NativeGitRepositoryService()

        let filtered = try service.loadLogSnapshot(
            at: repositoryURL.path(),
            query: WorkspaceGitLogQuery(since: "2025-01-01T00:00:00Z")
        )

        XCTAssertEqual(filtered.commits.count, 1)
        XCTAssertEqual(filtered.commits.first?.subject, "feat: fresh commit")
    }

    func testLoadLogAuthorsReturnsDistinctSortedAuthors() throws {
        let fixture = try GitRepositoryFixture()
        let repositoryURL = try fixture.createRepository(named: "git-log-authors")

        _ = try fixture.createCommit(
            in: repositoryURL,
            message: "feat: alice commit",
            fileName: "Alice.swift",
            content: "alice\n",
            environment: fixture.gitIdentityEnvironment(name: "Alice", email: "alice@example.com")
        )
        _ = try fixture.createCommit(
            in: repositoryURL,
            message: "feat: bob commit",
            fileName: "Bob.swift",
            content: "bob\n",
            environment: fixture.gitIdentityEnvironment(name: "Bob", email: "bob@example.com")
        )
        _ = try fixture.createCommit(
            in: repositoryURL,
            message: "feat: alice again",
            fileName: "AliceAgain.swift",
            content: "alice-again\n",
            environment: fixture.gitIdentityEnvironment(name: "Alice", email: "alice@example.com")
        )

        let service = NativeGitRepositoryService()

        let authors = try service.loadLogAuthors(at: repositoryURL.path())

        XCTAssertEqual(authors, ["Alice", "Bob", "DevHaven"])
    }

    func testLoadDiffForCommitFileReturnsOnlySelectedFilePatch() throws {
        let fixture = try GitRepositoryFixture()
        let repositoryURL = try fixture.createRepository(named: "git-file-diff")
        try FileManager.default.createDirectory(
            at: repositoryURL.appending(path: "Sources", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        try "hello\nreadme-updated\n".write(
            to: repositoryURL.appending(path: "README.md"),
            atomically: true,
            encoding: .utf8
        )
        try "final class App {}\n".write(
            to: repositoryURL.appending(path: "Sources/App.swift"),
            atomically: true,
            encoding: .utf8
        )
        try fixture.run(["git", "add", "README.md", "Sources/App.swift"], at: repositoryURL)
        try fixture.run(["git", "commit", "-m", "feat: update readme and app"], at: repositoryURL)
        let commitHash = try fixture.gitOutput(["git", "rev-parse", "HEAD"], at: repositoryURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let service = NativeGitRepositoryService()

        let fileDiff = try service.loadDiffForCommitFile(
            at: repositoryURL.path(),
            commitHash: commitHash,
            filePath: "README.md"
        )

        XCTAssertTrue(fileDiff.contains("README.md"))
        XCTAssertFalse(fileDiff.contains("Sources/App.swift"))
        XCTAssertTrue(fileDiff.contains("+readme-updated"))
    }

    func testLoadDiffForCommitFileOnMergeCommitUsesFirstParentPatchFormat() throws {
        let fixture = try GitRepositoryFixture()
        let repositoryURL = try fixture.createRepository(named: "git-merge-file-diff")

        try "base-top\nshared-middle\nbase-bottom\n".write(
            to: repositoryURL.appending(path: "README.md"),
            atomically: true,
            encoding: .utf8
        )
        try fixture.run(["git", "add", "README.md"], at: repositoryURL)
        try fixture.run(["git", "commit", "-m", "base: two-line readme"], at: repositoryURL, environment: fixture.gitIdentityEnvironment())

        try fixture.run(["git", "checkout", "-b", "feature/diff"], at: repositoryURL)
        try "feature-top\nshared-middle\nbase-bottom\n".write(
            to: repositoryURL.appending(path: "README.md"),
            atomically: true,
            encoding: .utf8
        )
        try fixture.run(["git", "add", "README.md"], at: repositoryURL)
        try fixture.run(["git", "commit", "-m", "feat: update first line"], at: repositoryURL, environment: fixture.gitIdentityEnvironment())

        try fixture.run(["git", "checkout", "main"], at: repositoryURL)
        try "base-top\nshared-middle\nmain-bottom\n".write(
            to: repositoryURL.appending(path: "README.md"),
            atomically: true,
            encoding: .utf8
        )
        try fixture.run(["git", "add", "README.md"], at: repositoryURL)
        try fixture.run(["git", "commit", "-m", "fix: update second line"], at: repositoryURL, environment: fixture.gitIdentityEnvironment())

        try fixture.run(
            ["git", "merge", "--no-ff", "feature/diff", "-m", "Merge branch 'feature/diff'"],
            at: repositoryURL,
            environment: fixture.gitIdentityEnvironment()
        )
        let mergeCommitHash = try fixture.gitOutput(["git", "rev-parse", "HEAD"], at: repositoryURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let service = NativeGitRepositoryService()
        let fileDiff = try service.loadDiffForCommitFile(
            at: repositoryURL.path(),
            commitHash: mergeCommitHash,
            filePath: "README.md"
        )
        let parsed = WorkspaceDiffPatchParser.parse(fileDiff)

        XCTAssertTrue(fileDiff.contains("diff --git a/README.md b/README.md"))
        XCTAssertFalse(fileDiff.contains("diff --cc README.md"))
        XCTAssertTrue(fileDiff.contains("@@ "))
        XCTAssertFalse(fileDiff.contains("@@@"))
        XCTAssertEqual(parsed.kind, .text)
    }

    func testLoadChangesSnapshotParsesPathsWithSpacesAndRename() throws {
        let fixture = try GitRepositoryFixture()
        let repositoryURL = try fixture.createRepository(named: "git-space-paths")

        _ = try fixture.createCommit(
            in: repositoryURL,
            message: "feat: add tracked spaced file",
            fileName: "tracked file.txt",
            content: "line-1\n"
        )
        _ = try fixture.createCommit(
            in: repositoryURL,
            message: "feat: add rename source",
            fileName: "rename source.txt",
            content: "rename me\n"
        )

        try "line-1\nline-2\n".write(
            to: repositoryURL.appending(path: "tracked file.txt"),
            atomically: true,
            encoding: .utf8
        )
        try fixture.run(
            ["git", "mv", "rename source.txt", "rename target.txt"],
            at: repositoryURL
        )

        try "temp\n".write(
            to: repositoryURL.appending(path: "untracked file.txt"),
            atomically: true,
            encoding: .utf8
        )

        let service = NativeGitRepositoryService()
        let snapshot = try service.loadChanges(at: repositoryURL.path())

        XCTAssertTrue(snapshot.unstaged.contains(where: { $0.path == "tracked file.txt" }))
        XCTAssertTrue(snapshot.staged.contains(where: {
            $0.path == "rename target.txt" && $0.originalPath == "rename source.txt"
        }))
        XCTAssertTrue(snapshot.untracked.contains(where: { $0.path == "untracked file.txt" }))
    }

    func testStageAndUnstageMutationsUpdateWorkingTreeSnapshot() throws {
        let fixture = try GitRepositoryFixture()
        let repositoryURL = try fixture.createRepository(named: "git-stage-unstage")
        try "hello\nchanged\n".write(
            to: repositoryURL.appending(path: "README.md"),
            atomically: true,
            encoding: .utf8
        )

        let service = NativeGitRepositoryService()
        try service.stage(paths: ["README.md"], at: repositoryURL.path())

        let stagedSnapshot = try service.loadChanges(at: repositoryURL.path())
        XCTAssertTrue(stagedSnapshot.staged.contains(where: { $0.path == "README.md" }))

        try service.unstage(paths: ["README.md"], at: repositoryURL.path())
        let unstagedSnapshot = try service.loadChanges(at: repositoryURL.path())
        XCTAssertTrue(unstagedSnapshot.unstaged.contains(where: { $0.path == "README.md" }))
        XCTAssertFalse(unstagedSnapshot.staged.contains(where: { $0.path == "README.md" }))
    }

    func testStageAllAndUnstageAllMutationsUpdateWorkingTreeSnapshot() throws {
        let fixture = try GitRepositoryFixture()
        let repositoryURL = try fixture.createRepository(named: "git-stage-all")
        try "hello\nchanged\n".write(
            to: repositoryURL.appending(path: "README.md"),
            atomically: true,
            encoding: .utf8
        )
        try "new\n".write(
            to: repositoryURL.appending(path: "new-file.txt"),
            atomically: true,
            encoding: .utf8
        )

        let service = NativeGitRepositoryService()
        try service.stageAll(at: repositoryURL.path())

        let stagedSnapshot = try service.loadChanges(at: repositoryURL.path())
        XCTAssertTrue(stagedSnapshot.staged.contains(where: { $0.path == "README.md" }))
        XCTAssertTrue(stagedSnapshot.staged.contains(where: { $0.path == "new-file.txt" }))

        try service.unstageAll(at: repositoryURL.path())
        let unstagedSnapshot = try service.loadChanges(at: repositoryURL.path())
        XCTAssertTrue(unstagedSnapshot.unstaged.contains(where: { $0.path == "README.md" }))
        XCTAssertTrue(unstagedSnapshot.untracked.contains(where: { $0.path == "new-file.txt" }))
    }

    func testDiscardMutationRestoresTrackedAndRemovesUntracked() throws {
        let fixture = try GitRepositoryFixture()
        let repositoryURL = try fixture.createRepository(named: "git-discard")
        try "hello\nchanged\n".write(
            to: repositoryURL.appending(path: "README.md"),
            atomically: true,
            encoding: .utf8
        )
        try "new\n".write(
            to: repositoryURL.appending(path: "temp.txt"),
            atomically: true,
            encoding: .utf8
        )

        let service = NativeGitRepositoryService()
        try service.discard(paths: ["README.md", "temp.txt"], at: repositoryURL.path())

        let snapshot = try service.loadChanges(at: repositoryURL.path())
        XCTAssertFalse(snapshot.unstaged.contains(where: { $0.path == "README.md" }))
        XCTAssertFalse(snapshot.untracked.contains(where: { $0.path == "temp.txt" }))
    }

    func testDiscardMutationDropsStagedTrackedChangesBackToHead() throws {
        let fixture = try GitRepositoryFixture()
        let repositoryURL = try fixture.createRepository(named: "git-discard-staged-tracked")
        try "hello\nstaged\n".write(
            to: repositoryURL.appending(path: "README.md"),
            atomically: true,
            encoding: .utf8
        )

        let service = NativeGitRepositoryService()
        try service.stage(paths: ["README.md"], at: repositoryURL.path())
        try service.discard(paths: ["README.md"], at: repositoryURL.path())

        let snapshot = try service.loadChanges(at: repositoryURL.path())
        XCTAssertFalse(snapshot.staged.contains(where: { $0.path == "README.md" }))
        XCTAssertFalse(snapshot.unstaged.contains(where: { $0.path == "README.md" }))
        let content = try String(contentsOf: repositoryURL.appending(path: "README.md"), encoding: .utf8)
        XCTAssertEqual(content, "hello\n")
    }

    func testDiscardMutationDropsStagedAddedFileFromIndexAndWorkingTree() throws {
        let fixture = try GitRepositoryFixture()
        let repositoryURL = try fixture.createRepository(named: "git-discard-staged-added")
        try "new\n".write(
            to: repositoryURL.appending(path: "NEW.txt"),
            atomically: true,
            encoding: .utf8
        )

        let service = NativeGitRepositoryService()
        try service.stage(paths: ["NEW.txt"], at: repositoryURL.path())
        try service.discard(paths: ["NEW.txt"], at: repositoryURL.path())

        let snapshot = try service.loadChanges(at: repositoryURL.path())
        XCTAssertFalse(snapshot.staged.contains(where: { $0.path == "NEW.txt" }))
        XCTAssertFalse(snapshot.untracked.contains(where: { $0.path == "NEW.txt" }))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repositoryURL.appending(path: "NEW.txt").path))
    }

    func testLoadHeadIndexAndLocalFileContentsReflectWorkingTreeState() throws {
        let fixture = try GitRepositoryFixture()
        let repositoryURL = try fixture.createRepository(named: "git-working-tree-contents")
        try "hello\nstaged\n".write(
            to: repositoryURL.appending(path: "README.md"),
            atomically: true,
            encoding: .utf8
        )
        try fixture.run(["git", "add", "README.md"], at: repositoryURL)
        try "hello\nstaged\nlocal\n".write(
            to: repositoryURL.appending(path: "README.md"),
            atomically: true,
            encoding: .utf8
        )

        let service = NativeGitRepositoryService()

        XCTAssertEqual(try service.loadHeadFileContent(at: repositoryURL.path(), filePath: "README.md"), "hello\n")
        XCTAssertEqual(try service.loadIndexFileContent(at: repositoryURL.path(), filePath: "README.md"), "hello\nstaged\n")
        XCTAssertEqual(try service.loadLocalFileContent(at: repositoryURL.path(), filePath: "README.md"), "hello\nstaged\nlocal\n")
    }

    func testLoadConflictFileContentsReturnsBaseOursTheirsAndResult() throws {
        let fixture = try GitRepositoryFixture()
        let repositoryURL = try fixture.createRepository(named: "git-conflict-contents")
        try fixture.run(["git", "checkout", "-b", "feature/conflict"], at: repositoryURL)
        _ = try fixture.createCommit(
            in: repositoryURL,
            message: "feat: feature readme",
            fileName: "README.md",
            content: "hello\nfeature\n"
        )
        try fixture.run(["git", "checkout", "main"], at: repositoryURL)
        _ = try fixture.createCommit(
            in: repositoryURL,
            message: "feat: main readme",
            fileName: "README.md",
            content: "hello\nmain\n"
        )

        let runner = NativeGitCommandRunner()
        let mergeResult = try runner.runAllowingFailure(arguments: ["merge", "feature/conflict"], at: repositoryURL.path())
        XCTAssertFalse(mergeResult.isSuccess)

        let service = NativeGitRepositoryService()
        let contents = try service.loadConflictFileContents(at: repositoryURL.path(), filePath: "README.md")

        XCTAssertEqual(contents.base, "hello\n")
        XCTAssertEqual(contents.ours, "hello\nmain\n")
        XCTAssertEqual(contents.theirs, "hello\nfeature\n")
        XCTAssertTrue(contents.result.contains("<<<<<<<"))
        XCTAssertTrue(contents.result.contains("main"))
        XCTAssertTrue(contents.result.contains("feature"))
    }

    func testStageAndUnstagePatchOnlyMutateIndex() throws {
        let fixture = try GitRepositoryFixture()
        let repositoryURL = try fixture.createRepository(named: "git-stage-patch")
        try "hello\none\ntwo\n".write(
            to: repositoryURL.appending(path: "README.md"),
            atomically: true,
            encoding: .utf8
        )

        let patch = """
diff --git a/README.md b/README.md
--- a/README.md
+++ b/README.md
@@ -1,0 +2,1 @@
+one
"""

        let service = NativeGitRepositoryService()
        try service.stagePatch(at: repositoryURL.path(), patch: patch)

        XCTAssertEqual(try service.loadIndexFileContent(at: repositoryURL.path(), filePath: "README.md"), "hello\none\n")
        XCTAssertEqual(try service.loadLocalFileContent(at: repositoryURL.path(), filePath: "README.md"), "hello\none\ntwo\n")

        try service.unstagePatch(at: repositoryURL.path(), patch: patch)

        XCTAssertEqual(try service.loadIndexFileContent(at: repositoryURL.path(), filePath: "README.md"), "hello\n")
        XCTAssertEqual(try service.loadLocalFileContent(at: repositoryURL.path(), filePath: "README.md"), "hello\none\ntwo\n")
    }

    func testDiscardMutationRevertsStagedRename() throws {
        let fixture = try GitRepositoryFixture()
        let repositoryURL = try fixture.createRepository(named: "git-discard-staged-rename")
        try fixture.run(["git", "mv", "README.md", "README-renamed.md"], at: repositoryURL)

        let service = NativeGitRepositoryService()
        try service.discard(paths: ["README-renamed.md"], at: repositoryURL.path())

        let snapshot = try service.loadChanges(at: repositoryURL.path())
        XCTAssertFalse(snapshot.staged.contains(where: { $0.path == "README-renamed.md" }))
        XCTAssertTrue(FileManager.default.fileExists(atPath: repositoryURL.appending(path: "README.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repositoryURL.appending(path: "README-renamed.md").path))
    }

    func testCommitAndAmendMutationsUpdateLatestCommit() throws {
        let fixture = try GitRepositoryFixture()
        let repositoryURL = try fixture.createRepository(named: "git-commit-amend")
        try "hello\ncommit\n".write(
            to: repositoryURL.appending(path: "README.md"),
            atomically: true,
            encoding: .utf8
        )

        let service = NativeGitRepositoryService()
        try service.stageAll(at: repositoryURL.path())
        try service.commit(message: "feat: commit readme", at: repositoryURL.path())

        try "hello\ncommit\namend\n".write(
            to: repositoryURL.appending(path: "README.md"),
            atomically: true,
            encoding: .utf8
        )
        try service.stage(paths: ["README.md"], at: repositoryURL.path())
        try service.amend(message: "feat: amend readme", at: repositoryURL.path())

        let snapshot = try service.loadLogSnapshot(at: repositoryURL.path())
        XCTAssertEqual(snapshot.commits.first?.subject, "feat: amend readme")
    }

    func testCreateCheckoutAndDeleteBranchMutations() throws {
        let fixture = try GitRepositoryFixture()
        let repositoryURL = try fixture.createRepository(named: "git-branch-mutations")

        let service = NativeGitRepositoryService()
        try service.createBranch(name: "feature/task4", startPoint: nil, at: repositoryURL.path())
        try service.checkoutBranch(name: "feature/task4", at: repositoryURL.path())

        let featureSnapshot = try service.loadChanges(at: repositoryURL.path())
        XCTAssertEqual(featureSnapshot.branchName, "feature/task4")

        try service.checkoutBranch(name: "main", at: repositoryURL.path())
        try service.deleteLocalBranch(name: "feature/task4", at: repositoryURL.path())

        let refs = try service.loadRefs(at: repositoryURL.path())
        XCTAssertFalse(refs.localBranches.contains(where: { $0.name == "feature/task4" }))
    }

    func testDeleteCurrentBranchMutationIsRejected() throws {
        let fixture = try GitRepositoryFixture()
        let repositoryURL = try fixture.createRepository(named: "git-delete-current-branch")

        let service = NativeGitRepositoryService()

        XCTAssertThrowsError(try service.deleteLocalBranch(name: "main", at: repositoryURL.path())) { error in
            guard case let WorkspaceGitCommandError.operationRejected(message) = error else {
                return XCTFail("应返回 operationRejected，实际：\(error)")
            }
            XCTAssertTrue(message.contains("当前分支"))
        }
    }

    func testFetchPullPushMutationsUpdateTrackingState() throws {
        let fixture = try GitRepositoryFixture()
        let remoteURL = try fixture.createBareRepository(named: "remote.git")
        let sourceURL = try fixture.createRepository(named: "source")
        try fixture.run(["git", "remote", "add", "origin", remoteURL.path()], at: sourceURL)
        try fixture.run(["git", "push", "-u", "origin", "main"], at: sourceURL)

        let consumerURL = try fixture.cloneRepository(from: remoteURL, named: "consumer")
        let service = NativeGitRepositoryService()

        _ = try fixture.createCommit(
            in: sourceURL,
            message: "feat: remote only",
            fileName: "REMOTE_ONLY.txt",
            content: "remote\n"
        )
        try fixture.run(["git", "push"], at: sourceURL)

        try service.fetch(at: consumerURL.path())
        let fetched = try service.loadAheadBehind(at: consumerURL.path())
        XCTAssertEqual(fetched.behind, 1)

        try service.pull(at: consumerURL.path())
        let pulled = try service.loadAheadBehind(at: consumerURL.path())
        XCTAssertEqual(pulled.ahead, 0)
        XCTAssertEqual(pulled.behind, 0)

        _ = try fixture.createCommit(
            in: consumerURL,
            message: "feat: consumer push",
            fileName: "CONSUMER_PUSH.txt",
            content: "push\n"
        )
        try service.push(at: consumerURL.path())

        try service.fetch(at: sourceURL.path())
        let sourceTracking = try service.loadAheadBehind(at: sourceURL.path())
        XCTAssertEqual(sourceTracking.behind, 1)
    }

    func testAbortOperationRejectsIdleRepository() throws {
        let fixture = try GitRepositoryFixture()
        let repositoryURL = try fixture.createRepository(named: "git-abort-idle")
        let service = NativeGitRepositoryService()

        XCTAssertThrowsError(try service.abortOperation(at: repositoryURL.path())) { error in
            guard case let WorkspaceGitCommandError.operationRejected(message) = error else {
                return XCTFail("应返回 operationRejected，实际：\(error)")
            }
            XCTAssertTrue(message.contains("没有可终止"))
        }
    }

    func testAbortOperationClearsMergeState() throws {
        let fixture = try GitRepositoryFixture()
        let repositoryURL = try fixture.createRepository(named: "git-abort-merge")
        let runner = NativeGitCommandRunner()

        try fixture.run(["git", "checkout", "-b", "feature/conflict"], at: repositoryURL)
        _ = try fixture.createCommit(
            in: repositoryURL,
            message: "feat: feature change",
            fileName: "README.md",
            content: "feature\n"
        )
        try fixture.run(["git", "checkout", "main"], at: repositoryURL)
        _ = try fixture.createCommit(
            in: repositoryURL,
            message: "feat: main change",
            fileName: "README.md",
            content: "main\n"
        )

        let mergeResult = try runner.runAllowingFailure(
            arguments: ["merge", "feature/conflict"],
            at: repositoryURL.path()
        )
        XCTAssertFalse(mergeResult.isSuccess)

        let service = NativeGitRepositoryService()
        XCTAssertEqual(try service.loadOperationState(at: repositoryURL.path()), .merging)

        try service.abortOperation(at: repositoryURL.path())

        XCTAssertEqual(try service.loadOperationState(at: repositoryURL.path()), .idle)
        let snapshot = try service.loadChanges(at: repositoryURL.path())
        XCTAssertTrue(snapshot.conflicted.isEmpty)
    }

    func testPushMutationMapsHookFailureToInteractionRequired() throws {
        let fixture = try GitRepositoryFixture()
        let remoteURL = try fixture.createBareRepository(named: "hook-remote.git")
        let repositoryURL = try fixture.createRepository(named: "hook-source")
        try fixture.run(["git", "remote", "add", "origin", remoteURL.path()], at: repositoryURL)
        try fixture.run(["git", "push", "-u", "origin", "main"], at: repositoryURL)

        let hookURL = repositoryURL
            .appending(path: ".git", directoryHint: .isDirectory)
            .appending(path: "hooks", directoryHint: .isDirectory)
            .appending(path: "pre-push")
        try FileManager.default.createDirectory(at: hookURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
#!/bin/sh
echo "pre-push hook requires terminal" 1>&2
exit 1
""".write(to: hookURL, atomically: true, encoding: .utf8)
        try fixture.run(["chmod", "+x", hookURL.path], at: repositoryURL)

        _ = try fixture.createCommit(
            in: repositoryURL,
            message: "feat: push blocked by hook",
            fileName: "HOOK.txt",
            content: "hook\n"
        )

        let service = NativeGitRepositoryService()
        XCTAssertThrowsError(try service.push(at: repositoryURL.path())) { error in
            guard case let WorkspaceGitCommandError.interactionRequired(command, reason) = error else {
                return XCTFail("应返回 interactionRequired，实际：\(error)")
            }
            XCTAssertTrue(command.contains("push"))
            XCTAssertTrue(reason.contains("hooks"))
        }
    }

    func testMutationsAreSerializedPerRootRepository() throws {
        let fixture = try GitRepositoryFixture()
        let rootURL = try fixture.createRepository(named: "git-serialization-root")
        let worktreeURL = fixture.homeURL.appending(path: "git-serialization-worktree", directoryHint: .isDirectory)
        try fixture.run(["git", "worktree", "add", worktreeURL.path(), "-b", "feature/serial"], at: rootURL)

        let commonGitDir = try fixture.gitOutput(
            ["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
            at: rootURL
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        let hookURL = URL(fileURLWithPath: commonGitDir)
            .appending(path: "hooks", directoryHint: .isDirectory)
            .appending(path: "pre-commit")
        try FileManager.default.createDirectory(at: hookURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
#!/bin/sh
sleep 0.35
""".write(to: hookURL, atomically: true, encoding: .utf8)
        try fixture.run(["chmod", "+x", hookURL.path], at: rootURL)

        try "root\n".write(to: rootURL.appending(path: "ROOT_SERIAL.txt"), atomically: true, encoding: .utf8)
        try "worktree\n".write(to: worktreeURL.appending(path: "WORKTREE_SERIAL.txt"), atomically: true, encoding: .utf8)

        let service = NativeGitRepositoryService()
        try service.stage(paths: ["ROOT_SERIAL.txt"], at: rootURL.path())
        try service.stage(paths: ["WORKTREE_SERIAL.txt"], at: worktreeURL.path())

        let errorBag = LockedStringBag()
        let group = DispatchGroup()
        let startedAt = Date()

        group.enter()
        DispatchQueue.global().async {
            defer { group.leave() }
            do {
                try service.commit(message: "feat: serial root", at: rootURL.path())
            } catch {
                errorBag.append(String(describing: error))
            }
        }

        group.enter()
        DispatchQueue.global().async {
            defer { group.leave() }
            do {
                try service.commit(message: "feat: serial worktree", at: worktreeURL.path())
            } catch {
                errorBag.append(String(describing: error))
            }
        }

        group.wait()
        let elapsed = Date().timeIntervalSince(startedAt)

        XCTAssertTrue(errorBag.values.isEmpty, "串行化后同 root repository 下并发 mutation 不应失败，实际错误：\(errorBag.values)")
        XCTAssertGreaterThanOrEqual(elapsed, 0.65, "两次 commit 应串行执行，耗时不应低于单次 hook 延迟的两倍")
    }

    func testGitCommandRunnerDrainsLargeStdoutWithoutTimeout() throws {
        let fixture = try GitRepositoryFixture()
        let repositoryURL = try fixture.createRepository(named: "git-runner-large-output")
        let largeContent = String(repeating: "0123456789abcdef\n", count: 12_000)
        let commitHash = try fixture.createCommit(
            in: repositoryURL,
            message: "feat: add large file",
            fileName: "LargeOutput.txt",
            content: largeContent
        )

        let runner = NativeGitCommandRunner(defaultTimeout: 2)
        let result = try runner.run(
            arguments: ["show", "--patch", "--format=", commitHash],
            at: repositoryURL.path(),
            timeout: 2
        )

        XCTAssertTrue(result.stdout.contains("diff --git a/LargeOutput.txt b/LargeOutput.txt"))
        XCTAssertGreaterThan(result.stdout.count, 100_000)
    }
}

private struct GitRepositoryFixture {
    let homeURL: URL

    init() throws {
        homeURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    }

    func createRepository(named name: String) throws -> URL {
        let url = homeURL.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try run(["git", "init", "-b", "main"], at: url)
        _ = try createCommit(in: url, message: "init", fileName: "README.md", content: "hello\n")
        return url
    }

    func createBareRepository(named name: String) throws -> URL {
        let url = homeURL.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try run(["git", "init", "--bare", "--initial-branch=main"], at: url)
        return url
    }

    func cloneRepository(from remoteURL: URL, named name: String) throws -> URL {
        let cloneURL = homeURL.appending(path: name, directoryHint: .isDirectory)
        try run(["git", "clone", remoteURL.path(), cloneURL.path()], at: homeURL)
        return cloneURL
    }

    @discardableResult
    func createCommit(
        in repositoryURL: URL,
        message: String,
        fileName: String,
        content: String,
        environment: [String: String]? = nil
    ) throws -> String {
        let fileURL = repositoryURL.appending(path: fileName)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        try run(["git", "add", fileName], at: repositoryURL)
        try run(["git", "commit", "-m", message], at: repositoryURL, environment: environment ?? gitIdentityEnvironment())
        return try gitOutput(["git", "rev-parse", "HEAD"], at: repositoryURL).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    func createEmptyCommit(in repositoryURL: URL, message: String) throws -> String {
        try run(["git", "commit", "--allow-empty", "-m", message], at: repositoryURL, environment: gitIdentityEnvironment())
        return try gitOutput(["git", "rev-parse", "HEAD"], at: repositoryURL).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func gitOutput(_ arguments: [String], at repositoryURL: URL) throws -> String {
        try run(arguments, at: repositoryURL).stdout
    }

    func graphLogSubjects(
        at repositoryURL: URL,
        additionalArguments: [String] = []
    ) throws -> [String] {
        let output = try gitOutput(
            [
                "git",
                "log",
                "--graph",
                "--all",
                "--pretty=format:%x1f%s",
                "-n",
                "300",
            ] + additionalArguments,
            at: repositoryURL
        )
        return output
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> String? in
                guard let separatorIndex = line.firstIndex(of: "\u{1f}") else {
                    return nil
                }
                return String(line[line.index(after: separatorIndex)...])
            }
    }

    @discardableResult
    func run(_ arguments: [String], at currentDirectoryURL: URL, environment: [String: String] = [:]) throws -> ProcessOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        let output = ProcessOutput(
            stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )

        guard process.terminationStatus == 0 else {
            throw TestFixtureError.commandFailed(
                arguments.joined(separator: " "),
                output.stderr.isEmpty ? output.stdout : output.stderr
            )
        }

        return output
    }

    func gitIdentityEnvironment(
        name: String = "DevHaven",
        email: String = "devhaven@example.com",
        authorDate: String? = nil,
        committerDate: String? = nil
    ) -> [String: String] {
        var environment = [
            "GIT_AUTHOR_NAME": name,
            "GIT_AUTHOR_EMAIL": email,
            "GIT_COMMITTER_NAME": name,
            "GIT_COMMITTER_EMAIL": email,
        ]
        if let authorDate {
            environment["GIT_AUTHOR_DATE"] = authorDate
        }
        if let committerDate {
            environment["GIT_COMMITTER_DATE"] = committerDate
        }
        return environment
    }
}

private struct ProcessOutput {
    let stdout: String
    let stderr: String
}

private enum TestFixtureError: Error, LocalizedError {
    case commandFailed(String, String)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(command, message):
            return "命令执行失败：\(command)\n\(message)"
        }
    }
}

private final class LockedStringBag: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ value: String) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
