import Foundation

@MainActor
final class WorkspaceDiffViewModelStore {
    private let repositoryService: NativeGitRepositoryService
    private let normalizePath: (String) -> String
    private var viewModelsByTabID: [String: WorkspaceDiffTabViewModel] = [:]

    init(
        repositoryService: NativeGitRepositoryService,
        normalizePath: @escaping (String) -> String
    ) {
        self.repositoryService = repositoryService
        self.normalizePath = normalizePath
    }

    func viewModel(
        for projectPath: String,
        tabID: String,
        diffTabsByProjectPath: [String: [WorkspaceDiffTabState]]
    ) -> WorkspaceDiffTabViewModel? {
        let normalizedProjectPath = normalizePath(projectPath)
        guard let tab = diffTabsByProjectPath[normalizedProjectPath]?.first(where: { $0.id == tabID }) else {
            return nil
        }
        if let existing = viewModelsByTabID[tabID] {
            return existing
        }
        let viewModel = WorkspaceDiffTabViewModel(
            tab: tab,
            client: .live(repositoryService: repositoryService)
        )
        viewModelsByTabID[tabID] = viewModel
        return viewModel
    }

    func openSessionIfLoaded(tabID: String, requestChain: WorkspaceDiffRequestChain) {
        viewModelsByTabID[tabID]?.openSession(requestChain)
    }

    func updateTabIfLoaded(tabID: String, tab: WorkspaceDiffTabState) {
        viewModelsByTabID[tabID]?.updateTab(tab)
    }

    func remove(tabID: String) {
        viewModelsByTabID[tabID] = nil
    }

    func removeTabs(_ tabs: [WorkspaceDiffTabState]) {
        for tab in tabs {
            viewModelsByTabID[tab.id] = nil
        }
    }

    func clearAll() {
        viewModelsByTabID.removeAll()
    }
}
