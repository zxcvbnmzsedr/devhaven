import XCTest
@testable import DevHavenCore

final class LegacyCompatStoreMutationTests: XCTestCase {
    func testUpdatingRecycleBinPreservesUnknownFields() throws {
        let fixture = try TestFixture()
        try fixture.writeAppState(
            """
            {
              "version": 4,
              "tags": [],
              "directories": ["/tmp/work"],
              "directProjectPaths": [],
              "recycleBin": ["/tmp/old"],
              "favoriteProjectPaths": [],
              "settings": {
                "terminalUseWebglRenderer": true,
                "terminalTheme": "DevHaven Dark",
                "gitIdentities": [],
                "projectListViewMode": "card",
                "viteDevPort": 1420,
                "webEnabled": true,
                "webBindHost": "0.0.0.0",
                "webBindPort": 3210,
                "unknownNested": "keep-settings"
              },
              "unknownFutureField": "keep-me"
            }
            """
        )

        let store = LegacyCompatStore(homeDirectoryURL: fixture.homeURL)
        try store.updateRecycleBin(["/tmp/new"])

        let json = try fixture.readJSON(named: "app_state.json")
        XCTAssertEqual(json["unknownFutureField"] as? String, "keep-me")
        XCTAssertEqual(json["recycleBin"] as? [String], ["/tmp/new"])
        let settings = try XCTUnwrap(json["settings"] as? [String: Any])
        XCTAssertEqual(settings["unknownNested"] as? String, "keep-settings")
    }

    func testUpdatingSettingsPreservesUnknownNestedFields() throws {
        let fixture = try TestFixture()
        try fixture.writeAppState(
            """
            {
              "version": 4,
              "tags": [],
              "directories": [],
              "directProjectPaths": [],
              "recycleBin": [],
              "favoriteProjectPaths": [],
              "settings": {
                "editorOpenTool": {
                  "commandPath": "",
                  "arguments": [],
                  "futureEditorFlag": true
                },
                "terminalOpenTool": {
                  "commandPath": "",
                  "arguments": []
                },
                "terminalUseWebglRenderer": false,
                "terminalTheme": "Old Theme",
                "gitIdentities": [],
                "projectListViewMode": "card",
                "viteDevPort": 1420,
                "webEnabled": true,
                "webBindHost": "0.0.0.0",
                "webBindPort": 3210,
                "futureRootFlag": "still-here"
              }
            }
            """
        )

        let store = LegacyCompatStore(homeDirectoryURL: fixture.homeURL)
        try store.updateSettings(
            AppSettings(
                editorOpenTool: OpenToolSettings(commandPath: "/usr/bin/open", arguments: ["-a", "Cursor"]),
                terminalOpenTool: OpenToolSettings(commandPath: "/usr/bin/open", arguments: ["-a", "Ghostty"]),
                terminalUseWebglRenderer: true,
                terminalTheme: "iTerm2 Solarized Dark",
                gitIdentities: [GitIdentity(name: "天增", email: "tianzeng@gmail.com")],
                projectListViewMode: .list,
                viteDevPort: 1410,
                webEnabled: true,
                webBindHost: "0.0.0.0",
                webBindPort: 3210
            )
        )

        let json = try fixture.readJSON(named: "app_state.json")
        let settings = try XCTUnwrap(json["settings"] as? [String: Any])
        XCTAssertEqual(settings["futureRootFlag"] as? String, "still-here")
        let editor = try XCTUnwrap(settings["editorOpenTool"] as? [String: Any])
        XCTAssertEqual(editor["futureEditorFlag"] as? Bool, true)
        XCTAssertEqual(settings["terminalTheme"] as? String, "iTerm2 Solarized Dark")
        XCTAssertEqual(settings["viteDevPort"] as? Int, 1410)
        XCTAssertEqual(settings["workspaceInAppNotificationsEnabled"] as? Bool, true)
        XCTAssertEqual(settings["workspaceNotificationSoundEnabled"] as? Bool, true)
        XCTAssertEqual(settings["workspaceSystemNotificationsEnabled"] as? Bool, false)
        XCTAssertEqual(settings["moveNotifiedWorktreeToTop"] as? Bool, true)
    }

    func testTodoMarkdownRoundTripUsesChecklistSyntax() {
        let items = [
            TodoItem(id: "1", text: "整理原生骨架", done: false),
            TodoItem(id: "2", text: "接入真实数据", done: true),
        ]

        let markdown = TodoMarkdownCodec.serialize(items)
        XCTAssertEqual(markdown, "- [ ] 整理原生骨架\n- [x] 接入真实数据")

        let parsed = TodoMarkdownCodec.parse(markdown)
        XCTAssertEqual(parsed.map(\.text), ["整理原生骨架", "接入真实数据"])
        XCTAssertEqual(parsed.map(\.done), [false, true])
    }
}

final class SnapshotLoadingTests: XCTestCase {
    func testLoadSnapshotReadsProjectsAndProjectDocuments() throws {
        let fixture = try TestFixture()
        let projectURL = fixture.homeURL.appending(path: "Projects/Alpha")
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        try "项目备注\n".write(to: projectURL.appending(path: "PROJECT_NOTES.md"), atomically: true, encoding: .utf8)
        try "- [x] 已存在待办\n".write(to: projectURL.appending(path: "PROJECT_TODO.md"), atomically: true, encoding: .utf8)
        try "# Alpha README\n".write(to: projectURL.appending(path: "README.md"), atomically: true, encoding: .utf8)

        try fixture.writeAppState(
            """
            {
              "version": 4,
              "tags": [],
              "directories": [],
              "directProjectPaths": ["\(projectURL.path())"],
              "recycleBin": [],
              "favoriteProjectPaths": [],
              "settings": {
                "editorOpenTool": {"commandPath": "", "arguments": []},
                "terminalOpenTool": {"commandPath": "", "arguments": []},
                "terminalUseWebglRenderer": true,
                "terminalTheme": "DevHaven Dark",
                "gitIdentities": [],
                "projectListViewMode": "card",
                "viteDevPort": 1420,
                "webEnabled": true,
                "webBindHost": "0.0.0.0",
                "webBindPort": 3210
              }
            }
            """
        )
        try fixture.writeProjects(
            """
            [
              {
                "id": "project-1",
                "name": "Alpha",
                "path": "\(projectURL.path())",
                "tags": ["native"],
                "runConfigurations": [],
                "worktrees": [],
                "mtime": 795000000,
                "size": 1024,
                "checksum": "checksum",
                "git_commits": 12,
                "git_last_commit": 795000123,
                "git_last_commit_message": "feat: initial native shell",
                "git_daily": "2026-03-19:3",
                "created": 795000000,
                "checked": 795000999
              }
            ]
            """
        )

        let store = LegacyCompatStore(homeDirectoryURL: fixture.homeURL)
        let snapshot = try store.loadSnapshot()
        XCTAssertEqual(snapshot.projects.count, 1)
        XCTAssertEqual(snapshot.appState.directProjectPaths, [projectURL.path()])

        let document = try store.loadProjectDocument(at: projectURL.path())
        XCTAssertEqual(document.notes, "项目备注\n")
        XCTAssertEqual(document.todoItems.count, 1)
        XCTAssertEqual(document.todoItems.first?.text, "已存在待办")
        XCTAssertEqual(document.readmeFallback?.path, "README.md")
    }
}

@MainActor
final class NativeAppViewModelTests: XCTestCase {
    func testSelectingProjectOpensDetailDrawerAndLoadsNotes() throws {
        let fixture = try TestFixture()
        let alphaURL = fixture.homeURL.appending(path: "Projects/Alpha")
        try FileManager.default.createDirectory(at: alphaURL, withIntermediateDirectories: true)
        try "原生详情备注\n".write(to: alphaURL.appending(path: "PROJECT_NOTES.md"), atomically: true, encoding: .utf8)

        try fixture.writeAppState(
            """
            {
              "version": 4,
              "tags": [],
              "directories": ["\(fixture.homeURL.appending(path: "Projects").path())"],
              "directProjectPaths": [],
              "recycleBin": [],
              "favoriteProjectPaths": [],
              "settings": {
                "projectListViewMode": "card",
                "terminalUseWebglRenderer": true,
                "terminalTheme": "DevHaven Dark",
                "gitIdentities": [],
                "viteDevPort": 1420,
                "webEnabled": true,
                "webBindHost": "0.0.0.0",
                "webBindPort": 3210
              }
            }
            """
        )
        try fixture.writeProjects(
            """
            [
              {
                "id": "alpha",
                "name": "Alpha",
                "path": "\(alphaURL.path())",
                "tags": [],
                "runConfigurations": [],
                "worktrees": [],
                "mtime": 795000000,
                "size": 1,
                "checksum": "a",
                "git_commits": 2,
                "git_last_commit": 795000111,
                "git_last_commit_message": "feat: alpha",
                "git_daily": null,
                "created": 795000000,
                "checked": 795000111
              }
            ]
            """
        )

        let viewModel = NativeAppViewModel(store: LegacyCompatStore(homeDirectoryURL: fixture.homeURL))
        viewModel.load()
        waitUntil(timeout: 2) { !viewModel.isProjectDocumentLoading }
        XCTAssertFalse(viewModel.isDetailPanelPresented)

        viewModel.selectProject(alphaURL.path())
        XCTAssertTrue(viewModel.isDetailPanelPresented)
        XCTAssertEqual(viewModel.selectedProject?.name, "Alpha")
        waitUntil(timeout: 2) { !viewModel.isProjectDocumentLoading }
        XCTAssertEqual(viewModel.notesDraft, "原生详情备注\n")
    }

    func testDirectoryAndTagFiltersNarrowProjectsLikeMainView() throws {
        let fixture = try TestFixture()
        let rootA = fixture.homeURL.appending(path: "Workspace/A")
        let rootB = fixture.homeURL.appending(path: "Workspace/B")
        try FileManager.default.createDirectory(at: rootA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootB, withIntermediateDirectories: true)

        try fixture.writeAppState(
            """
            {
              "version": 4,
              "tags": [
                {"name": "native", "color": {"r": 0.3, "g": 0.4, "b": 1, "a": 1}, "hidden": false},
                {"name": "server", "color": {"r": 0.2, "g": 0.9, "b": 0.4, "a": 1}, "hidden": false}
              ],
              "directories": ["\(rootA.path())", "\(rootB.path())"],
              "directProjectPaths": [],
              "recycleBin": [],
              "favoriteProjectPaths": [],
              "settings": {
                "projectListViewMode": "card",
                "terminalUseWebglRenderer": true,
                "terminalTheme": "DevHaven Dark",
                "gitIdentities": [],
                "viteDevPort": 1420,
                "webEnabled": true,
                "webBindHost": "0.0.0.0",
                "webBindPort": 3210
              }
            }
            """
        )
        try fixture.writeProjects(
            """
            [
              {
                "id": "a",
                "name": "Alpha",
                "path": "\(rootA.appending(path: "Alpha").path())",
                "tags": ["native"],
                "runConfigurations": [],
                "worktrees": [],
                "mtime": 795000000,
                "size": 1,
                "checksum": "a",
                "git_commits": 2,
                "git_last_commit": 795000111,
                "git_last_commit_message": "feat: alpha",
                "git_daily": "2026-03-18:2",
                "created": 795000000,
                "checked": 795000111
              },
              {
                "id": "b",
                "name": "Beta",
                "path": "\(rootB.appending(path: "Beta").path())",
                "tags": ["server"],
                "runConfigurations": [],
                "worktrees": [],
                "mtime": 795000000,
                "size": 1,
                "checksum": "b",
                "git_commits": 0,
                "git_last_commit": 0,
                "git_last_commit_message": null,
                "git_daily": null,
                "created": 795000000,
                "checked": 795000111
              }
            ]
            """
        )

        let viewModel = NativeAppViewModel(store: LegacyCompatStore(homeDirectoryURL: fixture.homeURL))
        viewModel.load()
        XCTAssertEqual(viewModel.filteredProjects.map(\.name), ["Alpha", "Beta"])

        viewModel.selectDirectory(.directory(rootA.path()))
        XCTAssertEqual(viewModel.filteredProjects.map(\.name), ["Alpha"])

        viewModel.selectDirectory(.all)
        viewModel.selectTag("server")
        XCTAssertEqual(viewModel.filteredProjects.map(\.name), ["Beta"])

        viewModel.selectTag(nil)
        viewModel.updateGitFilter(.gitOnly)
        XCTAssertEqual(viewModel.filteredProjects.map(\.name), ["Alpha"])
    }

    func testDirectProjectsVirtualDirectoryFiltersOnlyDirectProjectPaths() throws {
        let fixture = try TestFixture()
        let workspaceAlpha = fixture.homeURL.appending(path: "Workspace/Alpha")
        let directBeta = fixture.homeURL.appending(path: "Standalone/Beta")
        try FileManager.default.createDirectory(at: workspaceAlpha, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: directBeta, withIntermediateDirectories: true)

        try fixture.writeAppState(
            """
            {
              "version": 4,
              "tags": [],
              "directories": ["\(fixture.homeURL.appending(path: "Workspace").path())"],
              "directProjectPaths": ["\(directBeta.path())"],
              "recycleBin": [],
              "favoriteProjectPaths": [],
              "settings": {
                "projectListViewMode": "card",
                "terminalUseWebglRenderer": true,
                "terminalTheme": "DevHaven Dark",
                "gitIdentities": [],
                "viteDevPort": 1420,
                "webEnabled": true,
                "webBindHost": "0.0.0.0",
                "webBindPort": 3210
              }
            }
            """
        )
        try fixture.writeProjects(
            """
            [
              {
                "id": "alpha",
                "name": "Alpha",
                "path": "\(workspaceAlpha.path())",
                "tags": [],
                "runConfigurations": [],
                "worktrees": [],
                "mtime": 795000000,
                "size": 1,
                "checksum": "alpha",
                "git_commits": 0,
                "git_last_commit": 0,
                "git_last_commit_message": null,
                "git_daily": null,
                "created": 795000000,
                "checked": 795000111
              },
              {
                "id": "beta",
                "name": "Beta",
                "path": "\(directBeta.path())",
                "tags": [],
                "runConfigurations": [],
                "worktrees": [],
                "mtime": 795000000,
                "size": 1,
                "checksum": "beta",
                "git_commits": 0,
                "git_last_commit": 0,
                "git_last_commit_message": null,
                "git_daily": null,
                "created": 795000000,
                "checked": 795000111
              }
            ]
            """
        )

        let viewModel = NativeAppViewModel(store: LegacyCompatStore(homeDirectoryURL: fixture.homeURL))
        viewModel.load()

        XCTAssertTrue(viewModel.directoryRows.contains(where: { $0.title == "直接添加" && $0.filter == .directProjects }))

        viewModel.selectDirectory(.directProjects)

        XCTAssertEqual(viewModel.filteredProjects.map(\.path), [directBeta.path()])
        XCTAssertEqual(viewModel.selectedDirectory, .directProjects)
    }

    func testRefreshProjectCatalogMergesConfiguredDirectoriesAndDirectProjectPathsLikeArchiveRefresh() async throws {
        let fixture = try TestFixture()
        let workspaceRoot = fixture.homeURL.appending(path: "Workspace")
        let alphaURL = workspaceRoot.appending(path: "Alpha")
        let betaURL = fixture.homeURL.appending(path: "Standalone/Beta")
        try FileManager.default.createDirectory(at: alphaURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: betaURL, withIntermediateDirectories: true)

        try fixture.writeAppState(
            """
            {
              "version": 4,
              "tags": [],
              "directories": ["\(workspaceRoot.path())"],
              "directProjectPaths": ["\(betaURL.path())"],
              "recycleBin": [],
              "favoriteProjectPaths": [],
              "settings": {
                "projectListViewMode": "card",
                "terminalUseWebglRenderer": true,
                "terminalTheme": "DevHaven Dark",
                "gitIdentities": [],
                "viteDevPort": 1420,
                "webEnabled": true,
                "webBindHost": "0.0.0.0",
                "webBindPort": 3210
              }
            }
            """
        )
        try fixture.writeProjects("[]")

        let viewModel = NativeAppViewModel(store: LegacyCompatStore(homeDirectoryURL: fixture.homeURL))
        viewModel.load()
        XCTAssertTrue(viewModel.snapshot.projects.isEmpty)

        try await viewModel.refreshProjectCatalog()

        XCTAssertEqual(
            viewModel.snapshot.projects.map(\.path).sorted(),
            [alphaURL.path(), betaURL.path()].sorted()
        )
        XCTAssertEqual(viewModel.selectedDirectory, .all, "刷新项目列表不应偷偷改掉当前目录筛选")
    }

    func testRefreshProjectCatalogPreservesExistingGitMetadataForGitRepos() async throws {
        let fixture = try TestFixture()
        let workspaceRoot = fixture.homeURL.appending(path: "Workspace")
        let alphaURL = workspaceRoot.appending(path: "Alpha")
        try fixture.createGitRepository(
            at: alphaURL,
            commits: [
                .init(
                    fileName: "README.md",
                    content: "# Alpha\n",
                    authorName: "Alice",
                    authorEmail: "alice@example.com",
                    iso8601Date: "2026-03-10T10:00:00Z",
                    message: "feat: first"
                ),
                .init(
                    fileName: "README.md",
                    content: "# Alpha v2\n",
                    authorName: "Alice",
                    authorEmail: "alice@example.com",
                    iso8601Date: "2026-03-11T10:00:00Z",
                    message: "feat: second"
                ),
            ]
        )

        try fixture.writeAppState(
            """
            {
              "version": 4,
              "tags": [],
              "directories": ["\(workspaceRoot.path())"],
              "directProjectPaths": [],
              "recycleBin": [],
              "favoriteProjectPaths": [],
              "settings": {
                "projectListViewMode": "card",
                "terminalUseWebglRenderer": true,
                "terminalTheme": "DevHaven Dark",
                "gitIdentities": [],
                "viteDevPort": 1420,
                "webEnabled": true,
                "webBindHost": "0.0.0.0",
                "webBindPort": 3210
              }
            }
            """
        )
        try fixture.writeProjects(
            """
            [
              {
                "id": "alpha",
                "name": "Alpha",
                "path": "\(alphaURL.path())",
                "tags": [],
                "runConfigurations": [],
                "worktrees": [],
                "mtime": 795000000,
                "size": 1,
                "checksum": "a",
                "git_commits": 1,
                "git_last_commit": 795000000,
                "git_last_commit_message": "feat: first",
                "git_daily": "2026-03-10:1",
                "created": 795000000,
                "checked": 795000111
              }
            ]
            """
        )

        let viewModel = NativeAppViewModel(store: LegacyCompatStore(homeDirectoryURL: fixture.homeURL))
        viewModel.load()

        try await viewModel.refreshProjectCatalog()

        let project = try XCTUnwrap(viewModel.snapshot.projects.first)
        XCTAssertTrue(project.isGitRepository)
        XCTAssertEqual(project.gitCommits, 1)
        XCTAssertEqual(project.gitLastCommitMessage, "feat: first")
        XCTAssertEqual(project.gitDaily, "2026-03-10:1")
    }

    func testAddDirectProjectsPersistsPathsAndBuildsProjectsLikeArchiveSidebarAction() async throws {
        let fixture = try TestFixture()
        let betaURL = fixture.homeURL.appending(path: "Standalone/Beta")
        try FileManager.default.createDirectory(at: betaURL, withIntermediateDirectories: true)

        try fixture.writeAppState(
            """
            {
              "version": 4,
              "tags": [],
              "directories": [],
              "directProjectPaths": [],
              "recycleBin": [],
              "favoriteProjectPaths": [],
              "settings": {
                "projectListViewMode": "card",
                "terminalUseWebglRenderer": true,
                "terminalTheme": "DevHaven Dark",
                "gitIdentities": [],
                "viteDevPort": 1420,
                "webEnabled": true,
                "webBindHost": "0.0.0.0",
                "webBindPort": 3210
              }
            }
            """
        )
        try fixture.writeProjects("[]")

        let viewModel = NativeAppViewModel(store: LegacyCompatStore(homeDirectoryURL: fixture.homeURL))
        viewModel.load()

        try await viewModel.addDirectProjects([betaURL.path()])

        XCTAssertEqual(viewModel.snapshot.appState.directProjectPaths, [betaURL.path()])
        XCTAssertEqual(viewModel.snapshot.projects.map(\.path), [betaURL.path()])
        let appState = try fixture.readJSON(named: "app_state.json")
        XCTAssertEqual(appState["directProjectPaths"] as? [String], [betaURL.path()])
    }

    func testAddDirectProjectsRejectsGitWorktreePathInsteadOfSilentlyPersistingInvalidSource() async throws {
        let fixture = try TestFixture()
        let worktreeURL = fixture.homeURL.appending(path: "Standalone/Worktree")
        try FileManager.default.createDirectory(at: worktreeURL, withIntermediateDirectories: true)
        try """
        gitdir: \(fixture.homeURL.appending(path: "repo/.git/worktrees/demo").path())
        """.write(to: worktreeURL.appending(path: ".git"), atomically: true, encoding: .utf8)

        try fixture.writeAppState(
            """
            {
              "version": 4,
              "tags": [],
              "directories": [],
              "directProjectPaths": [],
              "recycleBin": [],
              "favoriteProjectPaths": [],
              "settings": {
                "projectListViewMode": "card",
                "terminalUseWebglRenderer": true,
                "terminalTheme": "DevHaven Dark",
                "gitIdentities": [],
                "viteDevPort": 1420,
                "webEnabled": true,
                "webBindHost": "0.0.0.0",
                "webBindPort": 3210
              }
            }
            """
        )
        try fixture.writeProjects("[]")

        let viewModel = NativeAppViewModel(store: LegacyCompatStore(homeDirectoryURL: fixture.homeURL))
        viewModel.load()

        do {
            try await viewModel.addDirectProjects([worktreeURL.path()])
            XCTFail("预期直接添加 worktree 会抛错，但实际未抛错")
        } catch {
            XCTAssertTrue(
                error.localizedDescription.contains("Git worktree"),
                "直接添加 worktree 时应给出明确错误，而不是静默无反应"
            )
        }

        XCTAssertEqual(viewModel.snapshot.appState.directProjectPaths, [])
        XCTAssertEqual(viewModel.snapshot.projects, [])
    }

    func testAddProjectDirectoryRejectsGitWorktreeRootInsteadOfPersistingEmptyDirectorySource() throws {
        let fixture = try TestFixture()
        let worktreeURL = fixture.homeURL.appending(path: "Workspace/Worktree")
        try FileManager.default.createDirectory(at: worktreeURL, withIntermediateDirectories: true)
        try """
        gitdir: \(fixture.homeURL.appending(path: "repo/.git/worktrees/demo").path())
        """.write(to: worktreeURL.appending(path: ".git"), atomically: true, encoding: .utf8)

        try fixture.writeAppState(
            """
            {
              "version": 4,
              "tags": [],
              "directories": [],
              "directProjectPaths": [],
              "recycleBin": [],
              "favoriteProjectPaths": [],
              "settings": {
                "projectListViewMode": "card",
                "terminalUseWebglRenderer": true,
                "terminalTheme": "DevHaven Dark",
                "gitIdentities": [],
                "viteDevPort": 1420,
                "webEnabled": true,
                "webBindHost": "0.0.0.0",
                "webBindPort": 3210
              }
            }
            """
        )
        try fixture.writeProjects("[]")

        let viewModel = NativeAppViewModel(store: LegacyCompatStore(homeDirectoryURL: fixture.homeURL))
        viewModel.load()

        XCTAssertThrowsError(
            try viewModel.addProjectDirectory(worktreeURL.path())
        ) { error in
            XCTAssertTrue(
                error.localizedDescription.contains("Git worktree"),
                "添加工作目录命中 worktree 根目录时应直接提示不支持，而不是把空目录来源静默写进配置"
            )
        }

        XCTAssertEqual(viewModel.snapshot.appState.directories, [])
        XCTAssertEqual(viewModel.snapshot.projects, [])
    }

    func testRemoveDirectProjectPersistsUpdatedPathsWithoutDeletingDiskProject() throws {
        let fixture = try TestFixture()
        let alphaURL = fixture.homeURL.appending(path: "Standalone/Alpha")
        let betaURL = fixture.homeURL.appending(path: "Standalone/Beta")
        try FileManager.default.createDirectory(at: alphaURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: betaURL, withIntermediateDirectories: true)

        try fixture.writeAppState(
            """
            {
              "version": 4,
              "tags": [],
              "directories": [],
              "directProjectPaths": ["\(alphaURL.path())", "\(betaURL.path())"],
              "recycleBin": [],
              "favoriteProjectPaths": [],
              "settings": {
                "projectListViewMode": "card",
                "terminalUseWebglRenderer": true,
                "terminalTheme": "DevHaven Dark",
                "gitIdentities": [],
                "viteDevPort": 1420,
                "webEnabled": true,
                "webBindHost": "0.0.0.0",
                "webBindPort": 3210
              }
            }
            """
        )
        try fixture.writeProjects(
            """
            [
              {
                "id": "alpha",
                "name": "Alpha",
                "path": "\(alphaURL.path())",
                "tags": [],
                "runConfigurations": [],
                "worktrees": [],
                "mtime": 795000000,
                "size": 1,
                "checksum": "alpha",
                "git_commits": 0,
                "git_last_commit": 0,
                "git_last_commit_message": null,
                "git_daily": null,
                "created": 795000000,
                "checked": 795000111
              },
              {
                "id": "beta",
                "name": "Beta",
                "path": "\(betaURL.path())",
                "tags": [],
                "runConfigurations": [],
                "worktrees": [],
                "mtime": 795000000,
                "size": 1,
                "checksum": "beta",
                "git_commits": 0,
                "git_last_commit": 0,
                "git_last_commit_message": null,
                "git_daily": null,
                "created": 795000000,
                "checked": 795000111
              }
            ]
            """
        )

        let viewModel = NativeAppViewModel(store: LegacyCompatStore(homeDirectoryURL: fixture.homeURL))
        viewModel.load()
        viewModel.selectDirectory(.directProjects)

        viewModel.removeDirectProject(betaURL.path())

        XCTAssertEqual(viewModel.snapshot.appState.directProjectPaths, [alphaURL.path()])
        XCTAssertEqual(viewModel.filteredProjects.map(\.path), [alphaURL.path()])
        XCTAssertTrue(FileManager.default.fileExists(atPath: betaURL.path()), "移除直连项目不应删除磁盘目录")

        let appState = try fixture.readJSON(named: "app_state.json")
        XCTAssertEqual(appState["directProjectPaths"] as? [String], [alphaURL.path()])
    }

    func testRemoveProjectDirectoryPersistsUpdatedDirectoriesAndClearsSelectedDirectoryFilter() async throws {
        let fixture = try TestFixture()
        let workspaceRoot = fixture.homeURL.appending(path: "Workspace")
        let alphaURL = workspaceRoot.appending(path: "Alpha")
        try FileManager.default.createDirectory(at: alphaURL, withIntermediateDirectories: true)

        try fixture.writeAppState(
            """
            {
              "version": 4,
              "tags": [],
              "directories": ["\(workspaceRoot.path())"],
              "directProjectPaths": [],
              "recycleBin": [],
              "favoriteProjectPaths": [],
              "settings": {
                "projectListViewMode": "card",
                "terminalUseWebglRenderer": true,
                "terminalTheme": "DevHaven Dark",
                "gitIdentities": [],
                "viteDevPort": 1420,
                "webEnabled": true,
                "webBindHost": "0.0.0.0",
                "webBindPort": 3210
              }
            }
            """
        )
        try fixture.writeProjects(
            """
            [
              {
                "id": "alpha",
                "name": "Alpha",
                "path": "\(alphaURL.path())",
                "tags": [],
                "runConfigurations": [],
                "worktrees": [],
                "mtime": 795000000,
                "size": 1,
                "checksum": "alpha",
                "git_commits": 0,
                "git_last_commit": 0,
                "git_last_commit_message": null,
                "git_daily": null,
                "created": 795000000,
                "checked": 795000111
              }
            ]
            """
        )

        let viewModel = NativeAppViewModel(store: LegacyCompatStore(homeDirectoryURL: fixture.homeURL))
        viewModel.load()
        viewModel.selectDirectory(.directory(workspaceRoot.path()))

        try await viewModel.removeProjectDirectory(workspaceRoot.path())

        XCTAssertEqual(viewModel.snapshot.appState.directories, [])
        XCTAssertEqual(viewModel.snapshot.projects, [])
        XCTAssertEqual(viewModel.selectedDirectory, .all, "删除当前选中的工作目录后，应回退到“全部”筛选，避免 UI 落在已消失的目录项上")
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspaceRoot.path()), "移除工作目录不应删除用户磁盘上的原始目录")

        let appState = try fixture.readJSON(named: "app_state.json")
        XCTAssertEqual(appState["directories"] as? [String], [])
    }

    func testHeatmapDateFilterOverridesTagSelectionAndBuildsActiveProjectList() throws {
        let fixture = try TestFixture()
        let rootA = fixture.homeURL.appending(path: "Workspace/A")
        let rootB = fixture.homeURL.appending(path: "Workspace/B")
        try FileManager.default.createDirectory(at: rootA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootB, withIntermediateDirectories: true)

        let selectedDateKey = dateKey(daysFromToday: -1)
        let previousDateKey = dateKey(daysFromToday: -3)

        try fixture.writeAppState(
            """
            {
              "version": 4,
              "tags": [
                {"name": "native", "color": {"r": 0.3, "g": 0.4, "b": 1, "a": 1}, "hidden": false},
                {"name": "server", "color": {"r": 0.2, "g": 0.9, "b": 0.4, "a": 1}, "hidden": false}
              ],
              "directories": ["\(rootA.path())", "\(rootB.path())"],
              "directProjectPaths": [],
              "recycleBin": [],
              "favoriteProjectPaths": [],
              "settings": {
                "projectListViewMode": "card",
                "terminalUseWebglRenderer": true,
                "terminalTheme": "DevHaven Dark",
                "gitIdentities": [],
                "viteDevPort": 1420,
                "webEnabled": true,
                "webBindHost": "0.0.0.0",
                "webBindPort": 3210
              }
            }
            """
        )
        try fixture.writeProjects(
            """
            [
              {
                "id": "a",
                "name": "Alpha",
                "path": "\(rootA.appending(path: "Alpha").path())",
                "tags": ["native"],
                "runConfigurations": [],
                "worktrees": [],
                "mtime": 795000000,
                "size": 1,
                "checksum": "a",
                "git_commits": 7,
                "git_last_commit": 795000111,
                "git_last_commit_message": "feat: alpha",
                "git_daily": "\(selectedDateKey):4,\(previousDateKey):1",
                "created": 795000000,
                "checked": 795000111
              },
              {
                "id": "b",
                "name": "Beta",
                "path": "\(rootB.appending(path: "Beta").path())",
                "tags": ["server"],
                "runConfigurations": [],
                "worktrees": [],
                "mtime": 795000100,
                "size": 1,
                "checksum": "b",
                "git_commits": 3,
                "git_last_commit": 795000211,
                "git_last_commit_message": "feat: beta",
                "git_daily": "\(selectedDateKey):2",
                "created": 795000000,
                "checked": 795000211
              }
            ]
            """
        )

        let viewModel = NativeAppViewModel(store: LegacyCompatStore(homeDirectoryURL: fixture.homeURL))
        viewModel.load()

        viewModel.selectTag("server")
        XCTAssertEqual(viewModel.filteredProjects.map(\.name), ["Beta"])

        viewModel.selectHeatmapDate(selectedDateKey)
        XCTAssertEqual(viewModel.selectedHeatmapDateKey, selectedDateKey)
        XCTAssertEqual(viewModel.filteredProjects.map(\.name), ["Alpha", "Beta"])
        XCTAssertEqual(viewModel.heatmapActiveProjects.map(\.name), ["Alpha", "Beta"])
        XCTAssertEqual(viewModel.heatmapActiveProjects.map(\.commitCount), [4, 2])

        viewModel.clearHeatmapDateFilter()
        XCTAssertNil(viewModel.selectedHeatmapDateKey)
        XCTAssertEqual(viewModel.filteredProjects.map(\.name), ["Beta"])
    }

    func testDashboardSummaryAggregatesRecentGitActivity() throws {
        let fixture = try TestFixture()
        let root = fixture.homeURL.appending(path: "Workspace")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let todayKey = dateKey(daysFromToday: 0)
        let recentKey = dateKey(daysFromToday: -5)
        let olderKey = dateKey(daysFromToday: -45)

        try fixture.writeAppState(
            """
            {
              "version": 4,
              "tags": [
                {"name": "native", "color": {"r": 0.3, "g": 0.4, "b": 1, "a": 1}, "hidden": false},
                {"name": "tooling", "color": {"r": 0.8, "g": 0.4, "b": 0.2, "a": 1}, "hidden": false}
              ],
              "directories": ["\(root.path())"],
              "directProjectPaths": [],
              "recycleBin": [],
              "favoriteProjectPaths": [],
              "settings": {
                "projectListViewMode": "card",
                "terminalUseWebglRenderer": true,
                "terminalTheme": "DevHaven Dark",
                "gitIdentities": [],
                "viteDevPort": 1420,
                "webEnabled": true,
                "webBindHost": "0.0.0.0",
                "webBindPort": 3210
              }
            }
            """
        )
        try fixture.writeProjects(
            """
            [
              {
                "id": "a",
                "name": "Alpha",
                "path": "\(root.appending(path: "Alpha").path())",
                "tags": ["native"],
                "runConfigurations": [],
                "worktrees": [],
                "mtime": 795000000,
                "size": 1,
                "checksum": "a",
                "git_commits": 8,
                "git_last_commit": 795000111,
                "git_last_commit_message": "feat: alpha",
                "git_daily": "\(todayKey):3,\(recentKey):2,\(olderKey):5",
                "created": 795000000,
                "checked": 795000111
              },
              {
                "id": "b",
                "name": "Beta",
                "path": "\(root.appending(path: "Beta").path())",
                "tags": ["tooling"],
                "runConfigurations": [],
                "worktrees": [],
                "mtime": 795000010,
                "size": 1,
                "checksum": "b",
                "git_commits": 1,
                "git_last_commit": 795000121,
                "git_last_commit_message": "chore: beta",
                "git_daily": "\(recentKey):1",
                "created": 795000000,
                "checked": 795000121
              }
            ]
            """
        )

        let viewModel = NativeAppViewModel(store: LegacyCompatStore(homeDirectoryURL: fixture.homeURL))
        viewModel.load()

        let summary = viewModel.gitDashboardSummary(for: .oneMonth)
        XCTAssertEqual(summary.projectCount, 2)
        XCTAssertEqual(summary.gitProjectCount, 2)
        XCTAssertEqual(summary.tagCount, 2)
        XCTAssertEqual(summary.activeDays, 2)
        XCTAssertEqual(summary.totalCommits, 6)
        XCTAssertEqual(summary.maxCommitsInDay, 3)
        XCTAssertEqual(summary.activityRate, 2.0 / 30.0, accuracy: 0.0001)

        let dailyActivities = viewModel.gitDashboardDailyActivities(for: .oneMonth)
        XCTAssertEqual(dailyActivities.count, 2)
        XCTAssertEqual(dailyActivities.first?.dateKey, todayKey)
        XCTAssertEqual(dailyActivities.first?.commitCount, 3)

        let activeProjects = viewModel.gitDashboardProjectActivities(for: .oneMonth)
        XCTAssertEqual(activeProjects.map(\.name), ["Alpha", "Beta"])
        XCTAssertEqual(activeProjects.map(\.commitCount), [5, 1])
    }

    func testGitDashboardLayoutPlanAdaptsToWindowWidth() {
        XCTAssertEqual(
            buildGitDashboardLayoutPlan(width: 560),
            GitDashboardLayoutPlan(statColumnCount: 2, stackSecondarySectionsVertically: true)
        )
        XCTAssertEqual(
            buildGitDashboardLayoutPlan(width: 920),
            GitDashboardLayoutPlan(statColumnCount: 2, stackSecondarySectionsVertically: true)
        )
        XCTAssertEqual(
            buildGitDashboardLayoutPlan(width: 1280),
            GitDashboardLayoutPlan(statColumnCount: 3, stackSecondarySectionsVertically: false)
        )
    }

    func testFilterChangeDoesNotReloadProjectDocumentWhenSelectionStaysSame() throws {
        let fixture = try TestFixture()
        let root = fixture.homeURL.appending(path: "Workspace")
        let alphaURL = root.appending(path: "Alpha")
        try FileManager.default.createDirectory(at: alphaURL, withIntermediateDirectories: true)
        try "原始备注\n".write(to: alphaURL.appending(path: "PROJECT_NOTES.md"), atomically: true, encoding: .utf8)

        try fixture.writeAppState(
            """
            {
              "version": 4,
              "tags": [],
              "directories": ["\(root.path())"],
              "directProjectPaths": [],
              "recycleBin": [],
              "favoriteProjectPaths": [],
              "settings": {
                "projectListViewMode": "card",
                "terminalUseWebglRenderer": true,
                "terminalTheme": "DevHaven Dark",
                "gitIdentities": [],
                "viteDevPort": 1420,
                "webEnabled": true,
                "webBindHost": "0.0.0.0",
                "webBindPort": 3210
              }
            }
            """
        )
        try fixture.writeProjects(
            """
            [
              {
                "id": "alpha",
                "name": "Alpha",
                "path": "\(alphaURL.path())",
                "tags": [],
                "runConfigurations": [],
                "worktrees": [],
                "mtime": 795000000,
                "size": 1,
                "checksum": "a",
                "git_commits": 2,
                "git_last_commit": 795000111,
                "git_last_commit_message": "feat: alpha",
                "git_daily": null,
                "created": 795000000,
                "checked": 795000111
              }
            ]
            """
        )

        let viewModel = NativeAppViewModel(store: LegacyCompatStore(homeDirectoryURL: fixture.homeURL))
        viewModel.load()
        waitUntil(timeout: 2) { !viewModel.isProjectDocumentLoading }
        XCTAssertEqual(viewModel.notesDraft, "原始备注\n")

        try Data([0xFF, 0xFE, 0x00]).write(to: alphaURL.appending(path: "PROJECT_NOTES.md"))

        viewModel.updateGitFilter(.gitOnly)

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.notesDraft, "原始备注\n")
    }

    func testToggleFavoriteDoesNotNeedSnapshotReloadForImmediateUiState() throws {
        let fixture = try TestFixture()
        let root = fixture.homeURL.appending(path: "Workspace")
        let alphaURL = root.appending(path: "Alpha")
        try FileManager.default.createDirectory(at: alphaURL, withIntermediateDirectories: true)

        try fixture.writeAppState(
            """
            {
              "version": 4,
              "tags": [],
              "directories": ["\(root.path())"],
              "directProjectPaths": [],
              "recycleBin": [],
              "favoriteProjectPaths": [],
              "settings": {
                "projectListViewMode": "card",
                "terminalUseWebglRenderer": true,
                "terminalTheme": "DevHaven Dark",
                "gitIdentities": [],
                "viteDevPort": 1420,
                "webEnabled": true,
                "webBindHost": "0.0.0.0",
                "webBindPort": 3210
              }
            }
            """
        )
        try fixture.writeProjects(
            """
            [
              {
                "id": "alpha",
                "name": "Alpha",
                "path": "\(alphaURL.path())",
                "tags": [],
                "runConfigurations": [],
                "worktrees": [],
                "mtime": 795000000,
                "size": 1,
                "checksum": "a",
                "git_commits": 2,
                "git_last_commit": 795000111,
                "git_last_commit_message": "feat: alpha",
                "git_daily": null,
                "created": 795000000,
                "checked": 795000111
              }
            ]
            """
        )

        let viewModel = NativeAppViewModel(store: LegacyCompatStore(homeDirectoryURL: fixture.homeURL))
        viewModel.load()

        try "not-json".write(to: fixture.homeURL.appending(path: ".devhaven/projects.json"), atomically: true, encoding: .utf8)

        viewModel.toggleProjectFavorite(alphaURL.path())

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.snapshot.appState.favoriteProjectPaths, [alphaURL.path()])
    }

    func testRefreshGitStatisticsReadsRealGitLogAndPreservesUnknownProjectFields() throws {
        let fixture = try TestFixture()
        let repoURL = fixture.homeURL.appending(path: "Workspace/Alpha")
        try fixture.createGitRepository(
            at: repoURL,
            commits: [
                .init(
                    fileName: "README.md",
                    content: "# Alpha\n",
                    authorName: "Alice",
                    authorEmail: "alice@example.com",
                    iso8601Date: "2026-03-10T09:00:00+08:00",
                    message: "feat: init"
                ),
                .init(
                    fileName: "README.md",
                    content: "# Alpha 2\n",
                    authorName: "Alice",
                    authorEmail: "alice@example.com",
                    iso8601Date: "2026-03-11T09:00:00+08:00",
                    message: "feat: update"
                ),
                .init(
                    fileName: "CHANGELOG.md",
                    content: "beta\n",
                    authorName: "Bob",
                    authorEmail: "bob@example.com",
                    iso8601Date: "2026-03-11T11:00:00+08:00",
                    message: "docs: bob"
                )
            ]
        )

        try fixture.writeAppState(
            """
            {
              "version": 4,
              "tags": [],
              "directories": ["\(fixture.homeURL.appending(path: "Workspace").path())"],
              "directProjectPaths": [],
              "recycleBin": [],
              "favoriteProjectPaths": [],
              "settings": {
                "projectListViewMode": "card",
                "terminalUseWebglRenderer": true,
                "terminalTheme": "DevHaven Dark",
                "gitIdentities": [
                  {"name": "Alice", "email": "alice@example.com"}
                ],
                "viteDevPort": 1420,
                "webEnabled": true,
                "webBindHost": "0.0.0.0",
                "webBindPort": 3210
              }
            }
            """
        )
        try fixture.writeProjects(
            """
            [
              {
                "id": "alpha",
                "name": "Alpha",
                "path": "\(repoURL.path())",
                "tags": [],
                "runConfigurations": [],
                "worktrees": [],
                "mtime": 795000000,
                "size": 1,
                "checksum": "a",
                "git_commits": 3,
                "git_last_commit": 795000111,
                "git_last_commit_message": "feat: update",
                "git_daily": null,
                "created": 795000000,
                "checked": 795000111,
                "futureField": "keep-me"
              }
            ]
            """
        )

        let viewModel = NativeAppViewModel(store: LegacyCompatStore(homeDirectoryURL: fixture.homeURL))
        viewModel.load()

        try viewModel.refreshGitStatistics()

        let snapshot = try fixture.readJSONArray(named: "projects.json")
        let project = try XCTUnwrap(snapshot.first as? [String: Any])
        XCTAssertEqual(project["futureField"] as? String, "keep-me")
        XCTAssertEqual(project["git_daily"] as? String, "2026-03-10:1,2026-03-11:1")
    }

    @MainActor
    func testRefreshGitStatisticsAsyncMarksRefreshingImmediatelyAndAppliesResults() async throws {
        let fixture = try TestFixture()
        let root = fixture.homeURL.appending(path: "Workspace")
        let alphaURL = root.appending(path: "Alpha")
        try FileManager.default.createDirectory(at: alphaURL, withIntermediateDirectories: true)

        try fixture.writeAppState(
            """
            {
              "version": 4,
              "tags": [],
              "directories": ["\(root.path())"],
              "directProjectPaths": [],
              "recycleBin": [],
              "favoriteProjectPaths": [],
              "settings": {
                "projectListViewMode": "card",
                "terminalUseWebglRenderer": true,
                "terminalTheme": "DevHaven Dark",
                "gitIdentities": [],
                "viteDevPort": 1420,
                "webEnabled": true,
                "webBindHost": "0.0.0.0",
                "webBindPort": 3210
              }
            }
            """
        )
        try fixture.writeProjects(
            """
            [
              {
                "id": "alpha",
                "name": "Alpha",
                "path": "\(alphaURL.path())",
                "tags": [],
                "runConfigurations": [],
                "worktrees": [],
                "mtime": 795000000,
                "size": 1,
                "checksum": "a",
                "git_commits": 3,
                "git_last_commit": 795000111,
                "git_last_commit_message": "feat: alpha",
                "git_daily": null,
                "created": 795000000,
                "checked": 795000111
              }
            ]
            """
        )

        let viewModel = NativeAppViewModel(
            store: LegacyCompatStore(homeDirectoryURL: fixture.homeURL),
            gitDailyCollectorAsync: { paths, _, progress in
                await progress(0, paths.count)
                try? await Task.sleep(for: .milliseconds(120))
                await progress(paths.count, paths.count)
                return paths.map { GitDailyRefreshResult(path: $0, gitDaily: "2026-03-19:3", error: nil) }
            }
        )
        viewModel.load()

        let task = Task {
            try await viewModel.refreshGitStatisticsAsync()
        }

        await Task.yield()
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(viewModel.isRefreshingGitStatistics)
        XCTAssertEqual(viewModel.gitStatisticsProgressText, "正在扫描 0/1 个 Git 仓库...")

        let summary = try await task.value
        XCTAssertFalse(viewModel.isRefreshingGitStatistics)
        XCTAssertNil(viewModel.gitStatisticsProgressText)
        XCTAssertEqual(summary.updatedRepositories, 1)
        XCTAssertEqual(viewModel.snapshot.projects.first?.gitDaily, "2026-03-19:3")
    }

    @MainActor
    func testRefreshGitStatisticsAsyncRefreshesGitMetadataForGitRepositoriesWithoutCommitCache() async throws {
        let fixture = try TestFixture()
        let root = fixture.homeURL.appending(path: "Workspace")
        let alphaURL = root.appending(path: "Alpha")
        try FileManager.default.createDirectory(at: alphaURL, withIntermediateDirectories: true)

        try fixture.writeAppState(
            """
            {
              "version": 4,
              "tags": [],
              "directories": ["\(root.path())"],
              "directProjectPaths": [],
              "recycleBin": [],
              "favoriteProjectPaths": [],
              "settings": {
                "projectListViewMode": "card",
                "terminalUseWebglRenderer": true,
                "terminalTheme": "DevHaven Dark",
                "gitIdentities": [],
                "viteDevPort": 1420,
                "webEnabled": true,
                "webBindHost": "0.0.0.0",
                "webBindPort": 3210
              }
            }
            """
        )
        try fixture.writeProjects(
            """
            [
              {
                "id": "alpha",
                "name": "Alpha",
                "path": "\(alphaURL.path())",
                "tags": [],
                "runConfigurations": [],
                "worktrees": [],
                "mtime": 795000000,
                "size": 1,
                "checksum": "a",
                "is_git_repository": true,
                "git_commits": 0,
                "git_last_commit": 0,
                "git_last_commit_message": null,
                "git_daily": null,
                "created": 795000000,
                "checked": 795000111
              }
            ]
            """
        )

        let viewModel = NativeAppViewModel(
            store: LegacyCompatStore(homeDirectoryURL: fixture.homeURL),
            gitDailyCollectorAsync: { paths, _, progress in
                await progress(0, paths.count)
                await progress(paths.count, paths.count)
                return paths.map {
                    GitDailyRefreshResult(
                        path: $0,
                        gitDaily: "2026-03-19:4",
                        gitCommits: 4,
                        gitLastCommit: 795000333,
                        gitLastCommitMessage: "feat: async refresh",
                        error: nil
                    )
                }
            }
        )
        viewModel.load()

        let summary = try await viewModel.refreshGitStatisticsAsync()

        XCTAssertEqual(summary.updatedRepositories, 1)
        let project = try XCTUnwrap(viewModel.snapshot.projects.first)
        XCTAssertEqual(project.gitCommits, 4)
        XCTAssertEqual(project.gitLastCommitMessage, "feat: async refresh")
        XCTAssertEqual(project.gitDaily, "2026-03-19:4")
    }

    func testGitOnlyFilterUsesIsGitRepositoryInsteadOfCommitCount() throws {
        let fixture = try TestFixture()
        let root = fixture.homeURL.appending(path: "Workspace")
        let alphaURL = root.appending(path: "Alpha")
        let betaURL = root.appending(path: "Beta")
        try FileManager.default.createDirectory(at: alphaURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: betaURL, withIntermediateDirectories: true)

        try fixture.writeAppState(
            """
            {
              "version": 4,
              "tags": [],
              "directories": ["\(root.path())"],
              "directProjectPaths": [],
              "recycleBin": [],
              "favoriteProjectPaths": [],
              "settings": {
                "projectListViewMode": "card",
                "terminalUseWebglRenderer": true,
                "terminalTheme": "DevHaven Dark",
                "gitIdentities": [],
                "viteDevPort": 1420,
                "webEnabled": true,
                "webBindHost": "0.0.0.0",
                "webBindPort": 3210
              }
            }
            """
        )
        try fixture.writeProjects(
            """
            [
              {
                "id": "alpha",
                "name": "Alpha",
                "path": "\(alphaURL.path())",
                "tags": [],
                "runConfigurations": [],
                "worktrees": [],
                "mtime": 795000000,
                "size": 1,
                "checksum": "a",
                "is_git_repository": true,
                "git_commits": 0,
                "git_last_commit": 0,
                "git_last_commit_message": null,
                "git_daily": null,
                "created": 795000000,
                "checked": 795000111
              },
              {
                "id": "beta",
                "name": "Beta",
                "path": "\(betaURL.path())",
                "tags": [],
                "runConfigurations": [],
                "worktrees": [],
                "mtime": 795000000,
                "size": 1,
                "checksum": "b",
                "is_git_repository": false,
                "git_commits": 0,
                "git_last_commit": 0,
                "git_last_commit_message": null,
                "git_daily": null,
                "created": 795000000,
                "checked": 795000111
              }
            ]
            """
        )

        let viewModel = NativeAppViewModel(store: LegacyCompatStore(homeDirectoryURL: fixture.homeURL))
        viewModel.load()
        viewModel.updateGitFilter(.gitOnly)

        XCTAssertEqual(viewModel.filteredProjects.map(\.name), ["Alpha"])
    }

    func testSelectingAnotherProjectStartsAsyncDocumentLoad() throws {
        let fixture = try TestFixture()
        let root = fixture.homeURL.appending(path: "Workspace")
        let alphaURL = root.appending(path: "Alpha")
        let betaURL = root.appending(path: "Beta")
        try FileManager.default.createDirectory(at: alphaURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: betaURL, withIntermediateDirectories: true)
        try "Alpha 备注\n".write(to: alphaURL.appending(path: "PROJECT_NOTES.md"), atomically: true, encoding: .utf8)
        try "Beta 备注\n".write(to: betaURL.appending(path: "PROJECT_NOTES.md"), atomically: true, encoding: .utf8)

        try fixture.writeAppState(
            """
            {
              "version": 4,
              "tags": [],
              "directories": ["\(root.path())"],
              "directProjectPaths": [],
              "recycleBin": [],
              "favoriteProjectPaths": [],
              "settings": {
                "projectListViewMode": "card",
                "terminalUseWebglRenderer": true,
                "terminalTheme": "DevHaven Dark",
                "gitIdentities": [],
                "viteDevPort": 1420,
                "webEnabled": true,
                "webBindHost": "0.0.0.0",
                "webBindPort": 3210
              }
            }
            """
        )
        try fixture.writeProjects(
            """
            [
              {
                "id": "alpha",
                "name": "Alpha",
                "path": "\(alphaURL.path())",
                "tags": [],
                "runConfigurations": [],
                "worktrees": [],
                "mtime": 795000000,
                "size": 1,
                "checksum": "a",
                "git_commits": 2,
                "git_last_commit": 795000111,
                "git_last_commit_message": "feat: alpha",
                "git_daily": null,
                "created": 795000000,
                "checked": 795000111
              },
              {
                "id": "beta",
                "name": "Beta",
                "path": "\(betaURL.path())",
                "tags": [],
                "runConfigurations": [],
                "worktrees": [],
                "mtime": 795000010,
                "size": 1,
                "checksum": "b",
                "git_commits": 2,
                "git_last_commit": 795000121,
                "git_last_commit_message": "feat: beta",
                "git_daily": null,
                "created": 795000000,
                "checked": 795000121
              }
            ]
            """
        )

        let viewModel = NativeAppViewModel(store: LegacyCompatStore(homeDirectoryURL: fixture.homeURL))
        viewModel.load()
        waitUntil(timeout: 2) { !viewModel.isProjectDocumentLoading }
        XCTAssertEqual(viewModel.selectedProject?.path, alphaURL.path())

        viewModel.selectProject(betaURL.path())

        XCTAssertEqual(viewModel.selectedProject?.path, betaURL.path())
        XCTAssertTrue(viewModel.isProjectDocumentLoading)
        waitUntil(timeout: 2) { !viewModel.isProjectDocumentLoading }
        XCTAssertEqual(viewModel.notesDraft, "Beta 备注\n")
    }

    func testLatestAsyncProjectDocumentResultWinsWhenSelectionsRace() throws {
        let fixture = try TestFixture()
        let root = fixture.homeURL.appending(path: "Workspace")
        let alphaURL = root.appending(path: "Alpha")
        let betaURL = root.appending(path: "Beta")
        let gammaURL = root.appending(path: "Gamma")
        try FileManager.default.createDirectory(at: alphaURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: betaURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: gammaURL, withIntermediateDirectories: true)

        try fixture.writeAppState(
            """
            {
              "version": 4,
              "tags": [],
              "directories": ["\(root.path())"],
              "directProjectPaths": [],
              "recycleBin": [],
              "favoriteProjectPaths": [],
              "settings": {
                "projectListViewMode": "card",
                "terminalUseWebglRenderer": true,
                "terminalTheme": "DevHaven Dark",
                "gitIdentities": [],
                "viteDevPort": 1420,
                "webEnabled": true,
                "webBindHost": "0.0.0.0",
                "webBindPort": 3210
              }
            }
            """
        )
        try fixture.writeProjects(
            """
            [
              {
                "id": "alpha",
                "name": "Alpha",
                "path": "\(alphaURL.path())",
                "tags": [],
                "runConfigurations": [],
                "worktrees": [],
                "mtime": 795000000,
                "size": 1,
                "checksum": "a",
                "git_commits": 2,
                "git_last_commit": 795000111,
                "git_last_commit_message": "feat: alpha",
                "git_daily": null,
                "created": 795000000,
                "checked": 795000111
              },
              {
                "id": "beta",
                "name": "Beta",
                "path": "\(betaURL.path())",
                "tags": [],
                "runConfigurations": [],
                "worktrees": [],
                "mtime": 795000010,
                "size": 1,
                "checksum": "b",
                "git_commits": 2,
                "git_last_commit": 795000121,
                "git_last_commit_message": "feat: beta",
                "git_daily": null,
                "created": 795000000,
                "checked": 795000121
              },
              {
                "id": "gamma",
                "name": "Gamma",
                "path": "\(gammaURL.path())",
                "tags": [],
                "runConfigurations": [],
                "worktrees": [],
                "mtime": 795000020,
                "size": 1,
                "checksum": "c",
                "git_commits": 2,
                "git_last_commit": 795000131,
                "git_last_commit_message": "feat: gamma",
                "git_daily": null,
                "created": 795000000,
                "checked": 795000131
              }
            ]
            """
        )

        let viewModel = NativeAppViewModel(
            store: LegacyCompatStore(homeDirectoryURL: fixture.homeURL),
            projectDocumentLoader: { path in
                switch path {
                case betaURL.path():
                    Thread.sleep(forTimeInterval: 0.12)
                    return ProjectDocumentSnapshot(notes: "Beta 备注\n", todoItems: [], readmeFallback: nil)
                case gammaURL.path():
                    Thread.sleep(forTimeInterval: 0.02)
                    return ProjectDocumentSnapshot(notes: "Gamma 备注\n", todoItems: [], readmeFallback: nil)
                default:
                    return ProjectDocumentSnapshot(notes: "Alpha 备注\n", todoItems: [], readmeFallback: nil)
                }
            }
        )

        viewModel.load()
        waitUntil(timeout: 2) { !viewModel.isProjectDocumentLoading }

        viewModel.selectProject(betaURL.path())
        viewModel.selectProject(gammaURL.path())

        waitUntil(timeout: 2) { !viewModel.isProjectDocumentLoading }
        XCTAssertEqual(viewModel.selectedProject?.path, gammaURL.path())
        XCTAssertEqual(viewModel.notesDraft, "Gamma 备注\n")

        waitUntil(timeout: 2) { !viewModel.isProjectDocumentLoading }
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        XCTAssertEqual(viewModel.notesDraft, "Gamma 备注\n")
    }
}

@MainActor
final class ProjectCatalogRefreshConcurrencyTests: XCTestCase {
    func testRefreshProjectCatalogExecutesInjectedRefresherOffMainThread() async throws {
        let fixture = try TestFixture()
        let workspaceRoot = fixture.homeURL.appending(path: "Workspace")
        try FileManager.default.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)

        try fixture.writeAppState(
            """
            {
              "version": 4,
              "tags": [],
              "directories": ["\(workspaceRoot.path())"],
              "directProjectPaths": [],
              "recycleBin": [],
              "favoriteProjectPaths": [],
              "settings": {
                "projectListViewMode": "card",
                "terminalUseWebglRenderer": true,
                "terminalTheme": "DevHaven Dark",
                "gitIdentities": [],
                "viteDevPort": 1420,
                "webEnabled": true,
                "webBindHost": "0.0.0.0",
                "webBindPort": 3210
              }
            }
            """
        )
        try fixture.writeProjects("[]")

        let recorder = RefreshInvocationRecorder()
        let viewModel = NativeAppViewModel(
            store: LegacyCompatStore(homeDirectoryURL: fixture.homeURL),
            projectCatalogRefresher: { _ in
                await recorder.record(isMainThread: pthread_main_np() != 0)
                return []
            }
        )
        viewModel.load()

        try await viewModel.refreshProjectCatalog()

        let invocationCount = await recorder.invocationCount()
        let recordedIsMainThread = await recorder.recordedIsMainThread()
        XCTAssertEqual(invocationCount, 1)
        XCTAssertEqual(recordedIsMainThread, [false])
    }

    func testRefreshProjectCatalogExposesRefreshingStateDuringBackgroundJob() async throws {
        let fixture = try TestFixture()
        let workspaceRoot = fixture.homeURL.appending(path: "Workspace")
        try FileManager.default.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)

        try fixture.writeAppState(
            """
            {
              "version": 4,
              "tags": [],
              "directories": ["\(workspaceRoot.path())"],
              "directProjectPaths": [],
              "recycleBin": [],
              "favoriteProjectPaths": [],
              "settings": {
                "projectListViewMode": "card",
                "terminalUseWebglRenderer": true,
                "terminalTheme": "DevHaven Dark",
                "gitIdentities": [],
                "viteDevPort": 1420,
                "webEnabled": true,
                "webBindHost": "0.0.0.0",
                "webBindPort": 3210
              }
            }
            """
        )
        try fixture.writeProjects("[]")

        let started = AsyncSignal()
        let release = AsyncSignal()
        let viewModel = NativeAppViewModel(
            store: LegacyCompatStore(homeDirectoryURL: fixture.homeURL),
            projectCatalogRefresher: { _ in
                await started.signal()
                await release.wait()
                return []
            }
        )
        viewModel.load()

        let task = Task<Void, Error> {
            try await viewModel.refreshProjectCatalog()
        }
        await started.wait()
        XCTAssertTrue(viewModel.isRefreshingProjectCatalog)

        await release.signal()
        try await task.value

        XCTAssertFalse(viewModel.isRefreshingProjectCatalog)
    }
}


private struct TestFixture {
    let homeURL: URL
    private let appDataURL: URL

    struct GitCommitSpec {
        let fileName: String
        let content: String
        let authorName: String
        let authorEmail: String
        let iso8601Date: String
        let message: String
    }

    init() throws {
        homeURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        appDataURL = homeURL.appending(path: ".devhaven", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: appDataURL, withIntermediateDirectories: true)
    }

    func writeAppState(_ content: String) throws {
        try content.write(to: appDataURL.appending(path: "app_state.json"), atomically: true, encoding: .utf8)
    }

    func writeProjects(_ content: String) throws {
        try content.write(to: appDataURL.appending(path: "projects.json"), atomically: true, encoding: .utf8)
    }

    func readJSON(named name: String) throws -> [String: Any] {
        let data = try Data(contentsOf: appDataURL.appending(path: name))
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }

    func readJSONArray(named name: String) throws -> [Any] {
        let data = try Data(contentsOf: appDataURL.appending(path: name))
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [Any])
    }

    func createGitRepository(at url: URL, commits: [GitCommitSpec]) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try run(["git", "init"], currentDirectoryURL: url)
        for commit in commits {
            let fileURL = url.appending(path: commit.fileName)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try commit.content.write(to: fileURL, atomically: true, encoding: .utf8)
            try run(["git", "add", commit.fileName], currentDirectoryURL: url)
            try run(
                ["git", "commit", "-m", commit.message],
                currentDirectoryURL: url,
                environment: [
                    "GIT_AUTHOR_NAME": commit.authorName,
                    "GIT_AUTHOR_EMAIL": commit.authorEmail,
                    "GIT_COMMITTER_NAME": commit.authorName,
                    "GIT_COMMITTER_EMAIL": commit.authorEmail,
                    "GIT_AUTHOR_DATE": commit.iso8601Date,
                    "GIT_COMMITTER_DATE": commit.iso8601Date,
                ]
            )
        }
    }

    private func run(_ arguments: [String], currentDirectoryURL: URL, environment: [String: String] = [:]) throws {
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

        guard process.terminationStatus == 0 else {
            let errorOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            XCTFail("命令执行失败：\(arguments.joined(separator: " "))\n\(errorOutput)")
            return
        }
    }
}

private func dateKey(daysFromToday: Int) -> String {
    let date = Calendar.current.date(byAdding: .day, value: daysFromToday, to: startOfToday()) ?? Date()
    let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 1, components.day ?? 1)
}

private func startOfToday() -> Date {
    Calendar.current.startOfDay(for: Date())
}

private actor RefreshInvocationRecorder {
    private var values: [Bool] = []

    func record(isMainThread: Bool) {
        values.append(isMainThread)
    }

    func invocationCount() -> Int {
        values.count
    }

    func recordedIsMainThread() -> [Bool] {
        values
    }
}

private actor AsyncSignal {
    private var hasSignaled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if hasSignaled {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        guard !hasSignaled else {
            return
        }
        hasSignaled = true
        let continuations = waiters
        waiters.removeAll()
        continuations.forEach { $0.resume() }
    }
}

@MainActor
private func waitUntil(timeout: TimeInterval, pollInterval: TimeInterval = 0.01, condition: @escaping () -> Bool) {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(pollInterval))
    }
}
