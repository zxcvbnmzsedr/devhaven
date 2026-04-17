import Foundation

@MainActor
final class WorkspaceFeatureViewModelStore {
    private let gitRepositoryService: NativeGitRepositoryService
    private let gitHubRepositoryService: NativeGitHubRepositoryService
    private let normalizePath: (String) -> String
    private let persistGitSelection: (String, String, String) -> Void
    private let resolveSelectionSnapshot: (String) -> WorkspaceGitSelectionSnapshot?

    private var commitViewModels: [String: WorkspaceCommitViewModel] = [:]
    private var gitViewModels: [String: WorkspaceGitViewModel] = [:]
    private var gitHubViewModels: [String: WorkspaceGitHubViewModel] = [:]

    init(
        gitRepositoryService: NativeGitRepositoryService,
        gitHubRepositoryService: NativeGitHubRepositoryService,
        normalizePath: @escaping (String) -> String,
        persistGitSelection: @escaping (String, String, String) -> Void,
        resolveSelectionSnapshot: @escaping (String) -> WorkspaceGitSelectionSnapshot?
    ) {
        self.gitRepositoryService = gitRepositoryService
        self.gitHubRepositoryService = gitHubRepositoryService
        self.normalizePath = normalizePath
        self.persistGitSelection = persistGitSelection
        self.resolveSelectionSnapshot = resolveSelectionSnapshot
    }

    func commitViewModel(for rootProjectPath: String) -> WorkspaceCommitViewModel? {
        commitViewModels[normalizePath(rootProjectPath)]
    }

    func gitViewModel(for rootProjectPath: String) -> WorkspaceGitViewModel? {
        gitViewModels[normalizePath(rootProjectPath)]
    }

    func gitHubViewModel(for rootProjectPath: String) -> WorkspaceGitHubViewModel? {
        gitHubViewModels[normalizePath(rootProjectPath)]
    }

    func prepareGitViewModel(for selectionSnapshot: WorkspaceGitSelectionSnapshot) {
        let repositoryContext = selectionSnapshot.gitContext
        let preferredExecutionPath = selectionSnapshot.commitContext.executionPath
        let executionWorktrees = repositoryContext.selectedRepositoryFamily?.members ?? []
        let normalizedRootProjectPath = normalizePath(repositoryContext.rootProjectPath)

        if let existing = gitViewModels[normalizedRootProjectPath] {
            existing.updateRepositoryContext(
                repositoryContext,
                executionWorktrees: executionWorktrees,
                preferredExecutionWorktreePath: preferredExecutionPath
            )
            existing.onRepositorySelectionChange = { [weak self] context, executionPath in
                self?.handleGitRepositorySelectionChange(
                    repositoryContext: context,
                    executionPath: executionPath
                )
            }
            return
        }

        let viewModel = WorkspaceGitViewModel(
            repositoryContext: repositoryContext,
            executionWorktrees: executionWorktrees,
            preferredExecutionWorktreePath: preferredExecutionPath,
            client: .live(service: gitRepositoryService)
        )
        viewModel.onRepositorySelectionChange = { [weak self] context, executionPath in
            self?.handleGitRepositorySelectionChange(
                repositoryContext: context,
                executionPath: executionPath
            )
        }
        gitViewModels[normalizedRootProjectPath] = viewModel
    }

    func prepareCommitViewModel(for repositoryContext: WorkspaceCommitRepositoryContext) {
        let normalizedRootProjectPath = normalizePath(repositoryContext.rootProjectPath)

        if let existing = commitViewModels[normalizedRootProjectPath] {
            existing.updateRepositoryContext(repositoryContext)
            existing.onRepositorySelectionChange = { [weak self] context in
                self?.handleCommitRepositorySelectionChange(context)
            }
            return
        }

        let viewModel = WorkspaceCommitViewModel(
            repositoryContext: repositoryContext,
            client: .live(service: gitRepositoryService)
        )
        viewModel.onRepositorySelectionChange = { [weak self] context in
            self?.handleCommitRepositorySelectionChange(context)
        }
        commitViewModels[normalizedRootProjectPath] = viewModel
    }

    func prepareGitHubViewModel(for selectionSnapshot: WorkspaceGitSelectionSnapshot) {
        let repositoryContext = selectionSnapshot.gitContext
        let executionPath = selectionSnapshot.commitContext.executionPath
        let normalizedRootProjectPath = normalizePath(repositoryContext.rootProjectPath)

        if let existing = gitHubViewModels[normalizedRootProjectPath] {
            existing.updateRepositoryContext(repositoryContext, executionPath: executionPath)
            return
        }

        gitHubViewModels[normalizedRootProjectPath] = WorkspaceGitHubViewModel(
            repositoryContext: repositoryContext,
            executionPath: executionPath,
            client: .live(
                githubService: gitHubRepositoryService,
                gitService: gitRepositoryService
            )
        )
    }

    func clearAll() {
        commitViewModels.removeAll()
        gitViewModels.removeAll()
        gitHubViewModels.removeAll()
    }

    private func handleGitRepositorySelectionChange(
        repositoryContext: WorkspaceGitRepositoryContext,
        executionPath: String
    ) {
        let normalizedRootProjectPath = normalizePath(repositoryContext.rootProjectPath)
        persistGitSelection(
            normalizedRootProjectPath,
            repositoryContext.selectedRepositoryFamilyID,
            executionPath
        )

        guard let selectionSnapshot = resolveSelectionSnapshot(normalizedRootProjectPath) else {
            return
        }

        if let commitViewModel = commitViewModels[normalizedRootProjectPath] {
            commitViewModel.updateRepositoryContext(selectionSnapshot.commitContext)
        }
        if let gitHubViewModel = gitHubViewModels[normalizedRootProjectPath] {
            gitHubViewModel.updateRepositoryContext(
                selectionSnapshot.gitContext,
                executionPath: selectionSnapshot.commitContext.executionPath
            )
        }
    }

    private func handleCommitRepositorySelectionChange(
        _ repositoryContext: WorkspaceCommitRepositoryContext
    ) {
        let normalizedRootProjectPath = normalizePath(repositoryContext.rootProjectPath)
        persistGitSelection(
            normalizedRootProjectPath,
            repositoryContext.selectedRepositoryFamilyID,
            repositoryContext.executionPath
        )

        guard let selectionSnapshot = resolveSelectionSnapshot(normalizedRootProjectPath) else {
            return
        }

        if let gitViewModel = gitViewModels[normalizedRootProjectPath] {
            let executionWorktrees = selectionSnapshot.gitContext.selectedRepositoryFamily?.members ?? []
            gitViewModel.updateRepositoryContext(
                selectionSnapshot.gitContext,
                executionWorktrees: executionWorktrees,
                preferredExecutionWorktreePath: selectionSnapshot.commitContext.executionPath
            )
        }
        if let gitHubViewModel = gitHubViewModels[normalizedRootProjectPath] {
            gitHubViewModel.updateRepositoryContext(
                selectionSnapshot.gitContext,
                executionPath: selectionSnapshot.commitContext.executionPath
            )
        }
        if let commitViewModel = commitViewModels[normalizedRootProjectPath],
           commitViewModel.repositoryContext != selectionSnapshot.commitContext {
            commitViewModel.updateRepositoryContext(selectionSnapshot.commitContext)
        }
    }
}
