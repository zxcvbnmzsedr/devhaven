import XCTest
@testable import DevHavenCore

@MainActor
final class NativeAppViewModelWorkspaceSidebarWidthTests: XCTestCase {
    func testLoadReadsPersistedWorkspaceSidebarWidth() throws {
        let fixture = try WorkspaceSidebarSettingsFixture()
        try fixture.writeAppState(workspaceSidebarWidth: 364)

        let viewModel = NativeAppViewModel(store: LegacyCompatStore(homeDirectoryURL: fixture.homeURL))
        viewModel.load()

        XCTAssertEqual(viewModel.workspaceSidebarWidth, 364)
    }

    func testUpdateWorkspaceSidebarWidthPersistsToSnapshotAndDisk() throws {
        let fixture = try WorkspaceSidebarSettingsFixture()
        try fixture.writeAppState(workspaceSidebarWidth: 280)

        let viewModel = NativeAppViewModel(store: LegacyCompatStore(homeDirectoryURL: fixture.homeURL))
        viewModel.load()
        viewModel.updateWorkspaceSidebarWidth(332)

        XCTAssertEqual(viewModel.workspaceSidebarWidth, 332)

        let json = try fixture.readAppStateJSON()
        let settings = try XCTUnwrap(json["settings"] as? [String: Any])
        XCTAssertEqual(settings["workspaceSidebarWidth"] as? Double, 332)
    }
}

private struct WorkspaceSidebarSettingsFixture {
    let homeURL: URL
    private let appDataURL: URL

    init() throws {
        homeURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        appDataURL = homeURL.appending(path: ".devhaven", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: appDataURL, withIntermediateDirectories: true)
    }

    func writeAppState(workspaceSidebarWidth: Double) throws {
        try """
        {
          "version": 4,
          "tags": [],
          "directories": [],
          "directProjectPaths": [],
          "recycleBin": [],
          "favoriteProjectPaths": [],
          "settings": {
            "editorOpenTool": {"commandPath": "", "arguments": []},
            "terminalOpenTool": {"commandPath": "", "arguments": []},
            "terminalUseWebglRenderer": true,
            "terminalTheme": "DevHaven Dark",
            "gitIdentities": [],
            "projectListViewMode": "card",
            "workspaceSidebarWidth": \(workspaceSidebarWidth),
            "viteDevPort": 1420,
            "webEnabled": true,
            "webBindHost": "0.0.0.0",
            "webBindPort": 3210
          }
        }
        """.write(to: appDataURL.appending(path: "app_state.json"), atomically: true, encoding: .utf8)
    }

    func readAppStateJSON() throws -> [String: Any] {
        let data = try Data(contentsOf: appDataURL.appending(path: "app_state.json"))
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }
}
