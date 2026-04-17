import XCTest
@testable import DevHavenCore

@MainActor
final class WorkspaceFeatureViewModelStoreTests: XCTestCase {
    func testPrepareCreatesAndReusesFeatureViewModels() {
        let harness = WorkspaceFeatureStoreHarness()
        let rootSnapshot = harness.makeSelectionSnapshot(
            selectedFamilyID: harness.rootFamily.id,
            executionPath: harness.rootFamily.preferredExecutionPath
        )
        harness.selectionSnapshots[harness.rootPath] = rootSnapshot

        harness.store.prepareGitViewModel(for: rootSnapshot)
        harness.store.prepareCommitViewModel(for: rootSnapshot.commitContext)
        harness.store.prepareGitHubViewModel(for: rootSnapshot)

        let gitViewModel = try? XCTUnwrap(harness.store.gitViewModel(for: harness.rootPath))
        let commitViewModel = try? XCTUnwrap(harness.store.commitViewModel(for: harness.rootPath))
        let gitHubViewModel = try? XCTUnwrap(harness.store.gitHubViewModel(for: harness.rootPath))

        let featureSnapshot = harness.makeSelectionSnapshot(
            selectedFamilyID: harness.featureFamily.id,
            executionPath: harness.featureFamily.preferredExecutionPath
        )
        harness.selectionSnapshots[harness.rootPath] = featureSnapshot

        harness.store.prepareGitViewModel(for: featureSnapshot)
        harness.store.prepareCommitViewModel(for: featureSnapshot.commitContext)
        harness.store.prepareGitHubViewModel(for: featureSnapshot)

        XCTAssertTrue(gitViewModel === harness.store.gitViewModel(for: harness.rootPath))
        XCTAssertTrue(commitViewModel === harness.store.commitViewModel(for: harness.rootPath))
        XCTAssertTrue(gitHubViewModel === harness.store.gitHubViewModel(for: harness.rootPath))
        XCTAssertEqual(harness.store.gitViewModel(for: harness.rootPath)?.selectedExecutionWorktreePath, harness.featurePath)
        XCTAssertEqual(harness.store.commitViewModel(for: harness.rootPath)?.repositoryContext.executionPath, harness.featurePath)
        XCTAssertEqual(harness.store.gitHubViewModel(for: harness.rootPath)?.executionPath, harness.featurePath)
    }

    func testGitSelectionChangeSyncsCommitAndGitHubContexts() throws {
        let harness = WorkspaceFeatureStoreHarness()
        let rootSnapshot = harness.makeSelectionSnapshot(
            selectedFamilyID: harness.rootFamily.id,
            executionPath: harness.rootFamily.preferredExecutionPath
        )
        harness.selectionSnapshots[harness.rootPath] = rootSnapshot
        harness.store.prepareGitViewModel(for: rootSnapshot)
        harness.store.prepareCommitViewModel(for: rootSnapshot.commitContext)
        harness.store.prepareGitHubViewModel(for: rootSnapshot)

        let featureSnapshot = harness.makeSelectionSnapshot(
            selectedFamilyID: harness.featureFamily.id,
            executionPath: harness.featureFamily.preferredExecutionPath
        )
        harness.selectionSnapshots[harness.rootPath] = featureSnapshot

        let gitViewModel = try XCTUnwrap(harness.store.gitViewModel(for: harness.rootPath))
        gitViewModel.onRepositorySelectionChange?(featureSnapshot.gitContext, harness.featurePath)

        XCTAssertEqual(harness.persistedFamilyIDByRoot[harness.rootPath], harness.featureFamily.id)
        XCTAssertEqual(harness.persistedExecutionPathByRoot[harness.rootPath], harness.featurePath)
        XCTAssertEqual(
            harness.store.commitViewModel(for: harness.rootPath)?.repositoryContext.selectedRepositoryFamilyID,
            harness.featureFamily.id
        )
        XCTAssertEqual(harness.store.commitViewModel(for: harness.rootPath)?.repositoryContext.executionPath, harness.featurePath)
        XCTAssertEqual(
            harness.store.gitHubViewModel(for: harness.rootPath)?.repositoryContext.selectedRepositoryFamilyID,
            harness.featureFamily.id
        )
        XCTAssertEqual(harness.store.gitHubViewModel(for: harness.rootPath)?.executionPath, harness.featurePath)
    }

    func testCommitSelectionChangeSyncsGitAndGitHubContexts() throws {
        let harness = WorkspaceFeatureStoreHarness()
        let rootSnapshot = harness.makeSelectionSnapshot(
            selectedFamilyID: harness.rootFamily.id,
            executionPath: harness.rootFamily.preferredExecutionPath
        )
        harness.selectionSnapshots[harness.rootPath] = rootSnapshot
        harness.store.prepareGitViewModel(for: rootSnapshot)
        harness.store.prepareCommitViewModel(for: rootSnapshot.commitContext)
        harness.store.prepareGitHubViewModel(for: rootSnapshot)

        let featureSnapshot = harness.makeSelectionSnapshot(
            selectedFamilyID: harness.featureFamily.id,
            executionPath: harness.featureFamily.preferredExecutionPath
        )
        harness.selectionSnapshots[harness.rootPath] = featureSnapshot

        let commitViewModel = try XCTUnwrap(harness.store.commitViewModel(for: harness.rootPath))
        commitViewModel.onRepositorySelectionChange?(featureSnapshot.commitContext)

        XCTAssertEqual(harness.persistedFamilyIDByRoot[harness.rootPath], harness.featureFamily.id)
        XCTAssertEqual(harness.persistedExecutionPathByRoot[harness.rootPath], harness.featurePath)
        XCTAssertEqual(
            harness.store.gitViewModel(for: harness.rootPath)?.repositoryContext.selectedRepositoryFamilyID,
            harness.featureFamily.id
        )
        XCTAssertEqual(harness.store.gitViewModel(for: harness.rootPath)?.selectedExecutionWorktreePath, harness.featurePath)
        XCTAssertEqual(
            harness.store.gitHubViewModel(for: harness.rootPath)?.repositoryContext.selectedRepositoryFamilyID,
            harness.featureFamily.id
        )
        XCTAssertEqual(harness.store.gitHubViewModel(for: harness.rootPath)?.executionPath, harness.featurePath)
    }
}

@MainActor
private final class WorkspaceFeatureStoreHarness {
    let rootPath = "/tmp/devhaven-root"
    let featurePath = "/tmp/devhaven-feature"
    let rootFamily: WorkspaceGitRepositoryFamilyContext
    let featureFamily: WorkspaceGitRepositoryFamilyContext
    var selectionSnapshots: [String: WorkspaceGitSelectionSnapshot] = [:]
    var persistedFamilyIDByRoot: [String: String] = [:]
    var persistedExecutionPathByRoot: [String: String] = [:]

    lazy var store = WorkspaceFeatureViewModelStore(
        gitRepositoryService: NativeGitRepositoryService(),
        gitHubRepositoryService: NativeGitHubRepositoryService(),
        normalizePath: { $0 },
        persistGitSelection: { [unowned self] rootProjectPath, familyID, executionPath in
            persistedFamilyIDByRoot[rootProjectPath] = familyID
            persistedExecutionPathByRoot[rootProjectPath] = executionPath
        },
        resolveSelectionSnapshot: { [unowned self] rootProjectPath in
            selectionSnapshots[rootProjectPath]
        }
    )

    init() {
        rootFamily = WorkspaceGitRepositoryFamilyContext(
            id: "family-root",
            displayName: "Root",
            repositoryPath: rootPath,
            preferredExecutionPath: rootPath,
            members: [
                WorkspaceGitWorktreeContext(
                    path: rootPath,
                    displayName: "Root",
                    branchName: "main",
                    isRootProject: true
                )
            ]
        )
        featureFamily = WorkspaceGitRepositoryFamilyContext(
            id: "family-feature",
            displayName: "Feature",
            repositoryPath: rootPath,
            preferredExecutionPath: featurePath,
            members: [
                WorkspaceGitWorktreeContext(
                    path: featurePath,
                    displayName: "Feature",
                    branchName: "feature/test",
                    isRootProject: false
                )
            ]
        )
    }

    func makeSelectionSnapshot(
        selectedFamilyID: String,
        executionPath: String
    ) -> WorkspaceGitSelectionSnapshot {
        let families = [rootFamily, featureFamily]
        let selectedFamily = families.first(where: { $0.id == selectedFamilyID }) ?? rootFamily
        let gitContext = WorkspaceGitRepositoryContext(
            rootProjectPath: rootPath,
            repositoryPath: selectedFamily.repositoryPath,
            repositoryFamilies: families,
            selectedRepositoryFamilyID: selectedFamily.id
        )
        let commitContext = WorkspaceCommitRepositoryContext(
            rootProjectPath: rootPath,
            repositoryPath: selectedFamily.repositoryPath,
            executionPath: executionPath,
            repositoryFamilies: families,
            selectedRepositoryFamilyID: selectedFamily.id
        )
        return WorkspaceGitSelectionSnapshot(
            gitContext: gitContext,
            commitContext: commitContext
        )
    }
}
