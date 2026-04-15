import Foundation
import XCTest
@testable import DevHavenCore

@MainActor
final class WorkspaceDiffTabViewModelTests: XCTestCase {
    func testLiveHistoryPreviewLoadsRenameAsReadOnlyCompareDocument() async throws {
        let fixture = try makeGitHistoryPreviewFixture()
        defer { try? FileManager.default.removeItem(at: fixture.repositoryURL) }

        let source = WorkspaceDiffSource.gitLogCommitFile(
            repositoryPath: fixture.repositoryURL.path,
            commitHash: fixture.renameCommitHash,
            filePath: "Sources/Renamed.swift"
        )
        let viewModel = WorkspaceDiffTabViewModel(
            tab: WorkspaceDiffTabState(
                id: "rename-history-tab",
                identity: source.identity,
                title: "Commit: Renamed.swift",
                source: source,
                viewerMode: .sideBySide,
                requestChain: WorkspaceDiffRequestChain(
                    items: [
                        WorkspaceDiffRequestItem(
                            id: source.identity,
                            title: "Commit: Renamed.swift",
                            source: source,
                            preferredViewerMode: .sideBySide,
                            paneMetadataSeeds: [
                                WorkspaceDiffPaneMetadataSeed(
                                    role: .left,
                                    title: "Before",
                                    path: "Sources/Original.swift",
                                    revision: fixture.initialCommitHash,
                                    hash: fixture.initialCommitHash
                                ),
                                WorkspaceDiffPaneMetadataSeed(
                                    role: .right,
                                    title: "After",
                                    path: "Sources/Renamed.swift",
                                    oldPath: "Sources/Original.swift",
                                    revision: fixture.renameCommitHash,
                                    hash: fixture.renameCommitHash
                                ),
                            ]
                        )
                    ]
                )
            ),
            client: .live(repositoryService: NativeGitRepositoryService())
        )

        viewModel.refresh()

        let loaded = await waitUntil(timeout: 2) {
            guard let document = viewModel.documentState.loadedCompareDocument else {
                return false
            }
            return document.mode == .history
                && document.leftPane.path == "Sources/Original.swift"
                && document.rightPane.path == "Sources/Renamed.swift"
                && document.leftPane.text == "struct Original {}\n"
                && document.rightPane.text == "struct Original {}\n"
                && document.blocks.isEmpty
                && document.rightPane.isEditable == false
        }

        XCTAssertTrue(loaded)
    }

    func testLiveHistoryPreviewLoadsAddedAndDeletedFilesAsCompareDocument() async throws {
        let fixture = try makeGitHistoryPreviewFixture()
        defer { try? FileManager.default.removeItem(at: fixture.repositoryURL) }

        let addedSource = WorkspaceDiffSource.gitLogCommitFile(
            repositoryPath: fixture.repositoryURL.path,
            commitHash: fixture.addCommitHash,
            filePath: "Sources/Added.swift"
        )
        let addedViewModel = WorkspaceDiffTabViewModel(
            tab: WorkspaceDiffTabState(
                id: "added-history-tab",
                identity: addedSource.identity,
                title: "Commit: Added.swift",
                source: addedSource,
                viewerMode: .sideBySide,
                requestChain: WorkspaceDiffRequestChain(
                    items: [
                        WorkspaceDiffRequestItem(
                            id: addedSource.identity,
                            title: "Commit: Added.swift",
                            source: addedSource,
                            preferredViewerMode: .sideBySide,
                            paneMetadataSeeds: [
                                WorkspaceDiffPaneMetadataSeed(
                                    role: .left,
                                    title: "Before",
                                    path: "Sources/Added.swift",
                                    revision: fixture.renameCommitHash,
                                    hash: fixture.renameCommitHash
                                ),
                                WorkspaceDiffPaneMetadataSeed(
                                    role: .right,
                                    title: "After",
                                    path: "Sources/Added.swift",
                                    revision: fixture.addCommitHash,
                                    hash: fixture.addCommitHash
                                ),
                            ]
                        )
                    ]
                )
            ),
            client: .live(repositoryService: NativeGitRepositoryService())
        )
        addedViewModel.refresh()

        let addedLoaded = await waitUntil(timeout: 2) {
            guard let document = addedViewModel.documentState.loadedCompareDocument else {
                return false
            }
            return document.mode == .history
                && document.leftPane.text.isEmpty
                && document.rightPane.text == "struct Added {}\n"
                && document.blocks.count == 1
        }
        XCTAssertTrue(addedLoaded)

        let deletedSource = WorkspaceDiffSource.gitLogCommitFile(
            repositoryPath: fixture.repositoryURL.path,
            commitHash: fixture.deleteCommitHash,
            filePath: "Sources/Renamed.swift"
        )
        let deletedViewModel = WorkspaceDiffTabViewModel(
            tab: WorkspaceDiffTabState(
                id: "deleted-history-tab",
                identity: deletedSource.identity,
                title: "Commit: Renamed.swift",
                source: deletedSource,
                viewerMode: .sideBySide,
                requestChain: WorkspaceDiffRequestChain(
                    items: [
                        WorkspaceDiffRequestItem(
                            id: deletedSource.identity,
                            title: "Commit: Renamed.swift",
                            source: deletedSource,
                            preferredViewerMode: .sideBySide,
                            paneMetadataSeeds: [
                                WorkspaceDiffPaneMetadataSeed(
                                    role: .left,
                                    title: "Before",
                                    path: "Sources/Renamed.swift",
                                    revision: fixture.addCommitHash,
                                    hash: fixture.addCommitHash
                                ),
                                WorkspaceDiffPaneMetadataSeed(
                                    role: .right,
                                    title: "After",
                                    path: "Sources/Renamed.swift",
                                    revision: fixture.deleteCommitHash,
                                    hash: fixture.deleteCommitHash
                                ),
                            ]
                        )
                    ]
                )
            ),
            client: .live(repositoryService: NativeGitRepositoryService())
        )
        deletedViewModel.refresh()

        let deletedLoaded = await waitUntil(timeout: 2) {
            guard let document = deletedViewModel.documentState.loadedCompareDocument else {
                return false
            }
            return document.mode == .history
                && document.leftPane.text == "struct Original {}\n"
                && document.rightPane.text.isEmpty
                && document.blocks.count == 1
        }
        XCTAssertTrue(deletedLoaded)
    }

    func testRefreshLoadsGitLogCommitFileAsReadOnlyCompareDocument() async throws {
        let source = WorkspaceDiffSource.gitLogCommitFile(
            repositoryPath: "/tmp/repo",
            commitHash: "abc123",
            filePath: "Sources/App.swift"
        )
        let paneMetadataSeeds = [
            WorkspaceDiffPaneMetadataSeed(
                role: .left,
                title: "Before",
                path: "Sources/App.swift",
                revision: "abc123^",
                hash: "abc123^"
            ),
            WorkspaceDiffPaneMetadataSeed(
                role: .right,
                title: "After",
                path: "Sources/App.swift",
                revision: "abc123",
                hash: "abc123"
            ),
        ]
        let requestChain = WorkspaceDiffRequestChain(
            items: [
                WorkspaceDiffRequestItem(
                    id: source.identity,
                    title: "Commit: App.swift",
                    source: source,
                    preferredViewerMode: .sideBySide,
                    paneMetadataSeeds: paneMetadataSeeds
                )
            ]
        )
        let viewModel = WorkspaceDiffTabViewModel(
            tab: WorkspaceDiffTabState(
                id: "git-log-diff-tab",
                identity: source.identity,
                title: "Commit: App.swift",
                source: source,
                viewerMode: .sideBySide,
                requestChain: requestChain
            ),
            client: .init(
                loadGitLogCommitFileDocument: { receivedSource, receivedSeeds in
                    XCTAssertEqual(receivedSource, source)
                    XCTAssertEqual(receivedSeeds, paneMetadataSeeds)
                    return .compare(
                        WorkspaceDiffCompareDocument(
                            mode: .history,
                            leftPane: WorkspaceDiffEditorPane(
                                title: "Before",
                                path: "Sources/App.swift",
                                text: "old line\nshared\n",
                                isEditable: false
                            ),
                            rightPane: WorkspaceDiffEditorPane(
                                title: "After",
                                path: "Sources/App.swift",
                                text: "new line\nshared\n",
                                isEditable: false
                            )
                        )
                    )
                },
                loadWorkingTreeDocument: { _ in
                    XCTFail("不应走 working tree diff 加载链路")
                    return .compare(
                        WorkspaceDiffCompareDocument(
                            mode: .unstaged,
                            leftPane: WorkspaceDiffEditorPane(title: "Staged", path: nil, text: "", isEditable: false),
                            rightPane: WorkspaceDiffEditorPane(title: "Local", path: nil, text: "", isEditable: true)
                        )
                    )
                },
                saveWorkingTreeFile: { _, _, _ in }
            ),
            editableContentRebuildDelayNanoseconds: 0
        )

        viewModel.refresh()

        let loaded = await waitUntil(timeout: 1) {
            guard let document = viewModel.documentState.loadedCompareDocument else {
                return false
            }
            return document.mode == .history
                && document.blocks.count == 1
                && document.leftPane.text == "old line\nshared\n"
                && document.rightPane.text == "new line\nshared\n"
                && document.rightPane.isEditable == false
        }

        XCTAssertTrue(loaded)
        XCTAssertEqual(viewModel.viewerDescriptor?.kind, .twoSide)
        XCTAssertEqual(viewModel.viewerDescriptor?.paneDescriptors.map(\.metadata.title), ["Before", "After"])
    }

    func testUpdateEditableCompareContentDefersDiffRebuildUntilDebounce() async throws {
        let viewModel = makeViewModel(rebuildDelayNanoseconds: 40_000_000)
        viewModel.documentState.loadState = .loaded(
            .compare(
                WorkspaceDiffCompareDocument(
                    mode: .unstaged,
                    leftPane: WorkspaceDiffEditorPane(
                        title: "Staged",
                        path: "Sources/App.swift",
                        text: "line 1\nline 2\n",
                        isEditable: false
                    ),
                    rightPane: WorkspaceDiffEditorPane(
                        title: "Local",
                        path: "Sources/App.swift",
                        text: "line 1\nline 2\n",
                        isEditable: true
                    ),
                    blocks: []
                )
            )
        )

        viewModel.updateEditableContent("line 1\nline x\n")

        let immediateDocument = try XCTUnwrap(viewModel.documentState.loadedCompareDocument)
        XCTAssertEqual(immediateDocument.rightPane.text, "line 1\nline x\n")
        XCTAssertTrue(immediateDocument.blocks.isEmpty, "输入后应先保留轻量文本更新，不立即主线程重算 diff")

        let rebuilt = await waitUntil(timeout: 1) {
            !(viewModel.documentState.loadedCompareDocument?.blocks.isEmpty ?? true)
        }
        XCTAssertTrue(rebuilt)

        let rebuiltDocument = try XCTUnwrap(viewModel.documentState.loadedCompareDocument)
        XCTAssertEqual(rebuiltDocument.rightPane.text, "line 1\nline x\n")
        XCTAssertEqual(rebuiltDocument.blocks.count, 1)
        XCTAssertEqual(rebuiltDocument.blocks.first?.rightLines, ["line x"])
    }

    func testLatestCompareEditWinsWhenPreviousRebuildIsCancelled() async throws {
        let viewModel = makeViewModel(rebuildDelayNanoseconds: 60_000_000)
        viewModel.documentState.loadState = .loaded(
            .compare(
                WorkspaceDiffCompareDocument(
                    mode: .unstaged,
                    leftPane: WorkspaceDiffEditorPane(
                        title: "Staged",
                        path: "Sources/App.swift",
                        text: "line 1\nline 2\n",
                        isEditable: false
                    ),
                    rightPane: WorkspaceDiffEditorPane(
                        title: "Local",
                        path: "Sources/App.swift",
                        text: "line 1\nline 2\n",
                        isEditable: true
                    ),
                    blocks: []
                )
            )
        )

        viewModel.updateEditableContent("line 1\nfirst\n")
        try await Task.sleep(nanoseconds: 10_000_000)
        viewModel.updateEditableContent("line 1\nsecond\n")

        let rebuilt = await waitUntil(timeout: 1) {
            viewModel.documentState.loadedCompareDocument?.blocks.first?.rightLines == ["second"]
        }
        XCTAssertTrue(rebuilt)

        let rebuiltDocument = try XCTUnwrap(viewModel.documentState.loadedCompareDocument)
        XCTAssertEqual(rebuiltDocument.rightPane.text, "line 1\nsecond\n")
        XCTAssertEqual(rebuiltDocument.blocks.first?.rightLines, ["second"])
    }

    func testUpdateEditableMergeContentDefersConflictRebuildUntilDebounce() async throws {
        let viewModel = makeViewModel(rebuildDelayNanoseconds: 40_000_000)
        viewModel.documentState.loadState = .loaded(
            .merge(
                WorkspaceDiffMergeDocument(
                    oursPane: WorkspaceDiffEditorPane(
                        title: "Ours",
                        path: "Sources/App.swift",
                        text: "A\n",
                        isEditable: false
                    ),
                    basePane: WorkspaceDiffEditorPane(
                        title: "Base",
                        path: "Sources/App.swift",
                        text: "",
                        isEditable: false
                    ),
                    theirsPane: WorkspaceDiffEditorPane(
                        title: "Theirs",
                        path: "Sources/App.swift",
                        text: "B\n",
                        isEditable: false
                    ),
                    resultPane: WorkspaceDiffEditorPane(
                        title: "Result",
                        path: "Sources/App.swift",
                        text: "",
                        isEditable: true
                    ),
                    conflictBlocks: []
                )
            )
        )

        viewModel.updateEditableContent("<<<<<<< ours\nA\n=======\nB\n>>>>>>> theirs\n")

        let immediateDocument = try XCTUnwrap(viewModel.documentState.loadedMergeDocument)
        XCTAssertEqual(immediateDocument.resultPane.text, "<<<<<<< ours\nA\n=======\nB\n>>>>>>> theirs\n")
        XCTAssertTrue(immediateDocument.conflictBlocks.isEmpty)

        let rebuilt = await waitUntil(timeout: 1) {
            !(viewModel.documentState.loadedMergeDocument?.conflictBlocks.isEmpty ?? true)
        }
        XCTAssertTrue(rebuilt)

        let rebuiltDocument = try XCTUnwrap(viewModel.documentState.loadedMergeDocument)
        XCTAssertEqual(rebuiltDocument.conflictBlocks.count, 1)
        XCTAssertEqual(rebuiltDocument.resultPane.text, "<<<<<<< ours\nA\n=======\nB\n>>>>>>> theirs\n")
    }

    private func makeViewModel(rebuildDelayNanoseconds: UInt64) -> WorkspaceDiffTabViewModel {
        WorkspaceDiffTabViewModel(
            tab: WorkspaceDiffTabState(
                id: "diff-tab",
                identity: "diff-tab",
                title: "Sources/App.swift",
                source: .workingTreeChange(
                    repositoryPath: "/tmp/repo",
                    executionPath: "/tmp/repo",
                    filePath: "Sources/App.swift",
                    group: .unstaged,
                    status: .modified,
                    oldPath: nil
                ),
                viewerMode: .sideBySide
            ),
            client: .init(
                loadGitLogCommitFileDocument: { _, _ in
                    .compare(
                        WorkspaceDiffCompareDocument(
                            mode: .history,
                            leftPane: WorkspaceDiffEditorPane(title: "Before", path: nil, text: "", isEditable: false),
                            rightPane: WorkspaceDiffEditorPane(title: "After", path: nil, text: "", isEditable: false)
                        )
                    )
                },
                loadWorkingTreeDocument: { _ in
                    WorkspaceDiffLoadedDocument.compare(
                        WorkspaceDiffCompareDocument(
                            mode: .unstaged,
                            leftPane: WorkspaceDiffEditorPane(title: "Staged", path: nil, text: "", isEditable: false),
                            rightPane: WorkspaceDiffEditorPane(title: "Local", path: nil, text: "", isEditable: true)
                        )
                    )
                },
                saveWorkingTreeFile: { _, _, _ in }
            ),
            editableContentRebuildDelayNanoseconds: rebuildDelayNanoseconds
        )
    }

    @discardableResult
    private func waitUntil(
        timeout: TimeInterval,
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }

    private func makeGitHistoryPreviewFixture() throws -> GitHistoryPreviewFixture {
        let repositoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("devhaven-history-preview-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)

        try runGit(["init"], at: repositoryURL)
        try runGit(["config", "user.name", "DevHaven Tests"], at: repositoryURL)
        try runGit(["config", "user.email", "tests@devhaven.local"], at: repositoryURL)

        let sourcesURL = repositoryURL.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sourcesURL, withIntermediateDirectories: true)

        let originalURL = sourcesURL.appendingPathComponent("Original.swift")
        try "struct Original {}\n".write(to: originalURL, atomically: true, encoding: .utf8)
        try runGit(["add", "Sources/Original.swift"], at: repositoryURL)
        try runGit(["commit", "-m", "Initial"], at: repositoryURL)
        let initialCommitHash = try runGit(["rev-parse", "HEAD"], at: repositoryURL)

        try runGit(["mv", "Sources/Original.swift", "Sources/Renamed.swift"], at: repositoryURL)
        try runGit(["commit", "-m", "Rename"], at: repositoryURL)
        let renameCommitHash = try runGit(["rev-parse", "HEAD"], at: repositoryURL)

        let addedURL = sourcesURL.appendingPathComponent("Added.swift")
        try "struct Added {}\n".write(to: addedURL, atomically: true, encoding: .utf8)
        try runGit(["add", "Sources/Added.swift"], at: repositoryURL)
        try runGit(["commit", "-m", "Add"], at: repositoryURL)
        let addCommitHash = try runGit(["rev-parse", "HEAD"], at: repositoryURL)

        try runGit(["rm", "Sources/Renamed.swift"], at: repositoryURL)
        try runGit(["commit", "-m", "Delete"], at: repositoryURL)
        let deleteCommitHash = try runGit(["rev-parse", "HEAD"], at: repositoryURL)

        return GitHistoryPreviewFixture(
            repositoryURL: repositoryURL,
            initialCommitHash: initialCommitHash,
            renameCommitHash: renameCommitHash,
            addCommitHash: addCommitHash,
            deleteCommitHash: deleteCommitHash
        )
    }

    @discardableResult
    private func runGit(_ arguments: [String], at repositoryURL: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = repositoryURL

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        let stdoutText = String(decoding: stdoutData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let stderrText = String(decoding: stderrData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "WorkspaceDiffTabViewModelTests.git",
                code: Int(process.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey: "git \(arguments.joined(separator: " ")) failed: \(stderrText)"
                ]
            )
        }
        return stdoutText
    }
}

private struct GitHistoryPreviewFixture {
    var repositoryURL: URL
    var initialCommitHash: String
    var renameCommitHash: String
    var addCommitHash: String
    var deleteCommitHash: String
}
