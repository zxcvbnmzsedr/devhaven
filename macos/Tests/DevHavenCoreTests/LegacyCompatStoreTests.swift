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
                "sharedScriptsRoot": "~/.devhaven/scripts",
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
                "sharedScriptsRoot": "~/.devhaven/scripts",
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
                sharedScriptsRoot: "~/.devhaven/scripts",
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
                "sharedScriptsRoot": "~/.devhaven/scripts",
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
                "scripts": [],
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
                "sharedScriptsRoot": "~/.devhaven/scripts",
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
                "scripts": [],
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
        XCTAssertFalse(viewModel.isDetailPanelPresented)

        viewModel.selectProject(alphaURL.path())
        XCTAssertTrue(viewModel.isDetailPanelPresented)
        XCTAssertEqual(viewModel.selectedProject?.name, "Alpha")
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
                "sharedScriptsRoot": "~/.devhaven/scripts",
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
                "scripts": [],
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
                "scripts": [],
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

        viewModel.selectDirectory(rootA.path())
        XCTAssertEqual(viewModel.filteredProjects.map(\.name), ["Alpha"])

        viewModel.selectDirectory(nil)
        viewModel.selectTag("server")
        XCTAssertEqual(viewModel.filteredProjects.map(\.name), ["Beta"])

        viewModel.selectTag(nil)
        viewModel.updateGitFilter(.gitOnly)
        XCTAssertEqual(viewModel.filteredProjects.map(\.name), ["Alpha"])
    }
}


private struct TestFixture {
    let homeURL: URL
    private let appDataURL: URL

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
}
