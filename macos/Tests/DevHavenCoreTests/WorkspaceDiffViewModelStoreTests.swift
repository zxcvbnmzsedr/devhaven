import XCTest
@testable import DevHavenCore

@MainActor
final class WorkspaceDiffViewModelStoreTests: XCTestCase {
    func testViewModelIsCreatedAndReusedForSameTab() throws {
        let store = WorkspaceDiffViewModelStore(
            repositoryService: NativeGitRepositoryService(),
            normalizePath: { $0 }
        )
        let projectPath = "/tmp/devhaven-diff-project"
        let tab = makeTab(id: "diff-1", title: "A.swift")
        let tabsByProjectPath = [projectPath: [tab]]

        let first = try XCTUnwrap(
            store.viewModel(
                for: projectPath,
                tabID: tab.id,
                diffTabsByProjectPath: tabsByProjectPath
            )
        )
        let second = try XCTUnwrap(
            store.viewModel(
                for: projectPath,
                tabID: tab.id,
                diffTabsByProjectPath: tabsByProjectPath
            )
        )

        XCTAssertTrue(first === second)
    }

    func testUpdateTabAndOpenSessionAffectLoadedViewModel() throws {
        let store = WorkspaceDiffViewModelStore(
            repositoryService: NativeGitRepositoryService(),
            normalizePath: { $0 }
        )
        let projectPath = "/tmp/devhaven-diff-project"
        let originalTab = makeTab(id: "diff-2", title: "Old.swift")
        let tabsByProjectPath = [projectPath: [originalTab]]
        let viewModel = try XCTUnwrap(
            store.viewModel(
                for: projectPath,
                tabID: originalTab.id,
                diffTabsByProjectPath: tabsByProjectPath
            )
        )

        var updatedTab = originalTab
        updatedTab.title = "New.swift"
        updatedTab.viewerMode = .unified
        store.updateTabIfLoaded(tabID: originalTab.id, tab: updatedTab)

        let requestChain = WorkspaceDiffRequestChain(
            items: [
                WorkspaceDiffRequestItem(
                    id: "req-1",
                    title: "Request",
                    source: updatedTab.source,
                    preferredViewerMode: .unified
                )
            ]
        )
        store.openSessionIfLoaded(tabID: originalTab.id, requestChain: requestChain)

        XCTAssertEqual(viewModel.tab.title, "Request")
        XCTAssertEqual(viewModel.tab.viewerMode, .unified)
        XCTAssertEqual(viewModel.sessionState.requestChain, requestChain)
    }

    func testRemoveAndRemoveTabsDiscardLoadedViewModels() throws {
        let store = WorkspaceDiffViewModelStore(
            repositoryService: NativeGitRepositoryService(),
            normalizePath: { $0 }
        )
        let projectPath = "/tmp/devhaven-diff-project"
        let firstTab = makeTab(id: "diff-3", title: "First.swift")
        let secondTab = makeTab(id: "diff-4", title: "Second.swift")
        let tabsByProjectPath = [projectPath: [firstTab, secondTab]]

        let firstLoaded = try XCTUnwrap(
            store.viewModel(
                for: projectPath,
                tabID: firstTab.id,
                diffTabsByProjectPath: tabsByProjectPath
            )
        )
        let secondLoaded = try XCTUnwrap(
            store.viewModel(
                for: projectPath,
                tabID: secondTab.id,
                diffTabsByProjectPath: tabsByProjectPath
            )
        )

        store.remove(tabID: firstTab.id)
        store.removeTabs([secondTab])

        let reloadedFirst = try XCTUnwrap(
            store.viewModel(
                for: projectPath,
                tabID: firstTab.id,
                diffTabsByProjectPath: tabsByProjectPath
            )
        )
        let reloadedSecond = try XCTUnwrap(
            store.viewModel(
                for: projectPath,
                tabID: secondTab.id,
                diffTabsByProjectPath: tabsByProjectPath
            )
        )

        XCTAssertFalse(firstLoaded === reloadedFirst)
        XCTAssertFalse(secondLoaded === reloadedSecond)
    }

    private func makeTab(id: String, title: String) -> WorkspaceDiffTabState {
        let source = WorkspaceDiffSource.gitLogCommitFile(
            repositoryPath: "/tmp/repo",
            commitHash: "abc123",
            filePath: title
        )
        return WorkspaceDiffTabState(
            id: id,
            identity: source.identity,
            title: title,
            source: source,
            viewerMode: .sideBySide
        )
    }
}
