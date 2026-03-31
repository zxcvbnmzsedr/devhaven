import Foundation
import Observation

@MainActor
@Observable
public final class WorkspaceDiffTabViewModel {
    private enum EditableContentRebuildRequest: Sendable {
        case compare(
            mode: WorkspaceDiffCompareMode,
            leftPane: WorkspaceDiffEditorPane,
            rightPane: WorkspaceDiffEditorPane
        )
        case merge(
            oursPane: WorkspaceDiffEditorPane,
            basePane: WorkspaceDiffEditorPane,
            theirsPane: WorkspaceDiffEditorPane,
            resultPane: WorkspaceDiffEditorPane
        )

        func buildDocument() -> WorkspaceDiffLoadedDocument {
            switch self {
            case let .compare(mode, leftPane, rightPane):
                return .compare(
                    buildCompareDocument(
                        mode: mode,
                        leftPane: leftPane,
                        rightPane: rightPane
                    )
                )
            case let .merge(oursPane, basePane, theirsPane, resultPane):
                return .merge(
                    buildMergeDocument(
                        oursPane: oursPane,
                        basePane: basePane,
                        theirsPane: theirsPane,
                        resultPane: resultPane
                    )
                )
            }
        }
    }

    private enum DifferenceSelectionPreference {
        case first
        case last
        case preserveCurrent
    }

    public struct Client: Sendable {
        public var loadGitLogCommitFileDiff: @Sendable (String, String, String) throws -> String
        public var loadWorkingTreeDocument: @Sendable (WorkspaceDiffSource) throws -> WorkspaceDiffLoadedDocument
        public var saveWorkingTreeFile: @Sendable (String, String, String) throws -> Void
        public var stageWorkingTreePatch: @Sendable (String, String) throws -> Void
        public var unstageWorkingTreePatch: @Sendable (String, String) throws -> Void

        public init(
            loadGitLogCommitFileDiff: @escaping @Sendable (String, String, String) throws -> String,
            loadWorkingTreeDocument: @escaping @Sendable (WorkspaceDiffSource) throws -> WorkspaceDiffLoadedDocument,
            saveWorkingTreeFile: @escaping @Sendable (String, String, String) throws -> Void,
            stageWorkingTreePatch: @escaping @Sendable (String, String) throws -> Void = { _, _ in },
            unstageWorkingTreePatch: @escaping @Sendable (String, String) throws -> Void = { _, _ in }
        ) {
            self.loadGitLogCommitFileDiff = loadGitLogCommitFileDiff
            self.loadWorkingTreeDocument = loadWorkingTreeDocument
            self.saveWorkingTreeFile = saveWorkingTreeFile
            self.stageWorkingTreePatch = stageWorkingTreePatch
            self.unstageWorkingTreePatch = unstageWorkingTreePatch
        }

        public static func live(
            repositoryService: NativeGitRepositoryService = NativeGitRepositoryService(),
            commitWorkflowService: NativeGitCommitWorkflowService? = nil
        ) -> Client {
            _ = commitWorkflowService
            return Client(
                loadGitLogCommitFileDiff: { repositoryPath, commitHash, filePath in
                    try repositoryService.loadDiffForCommitFile(at: repositoryPath, commitHash: commitHash, filePath: filePath)
                },
                loadWorkingTreeDocument: { source in
                    try buildWorkingTreeDocument(for: source, repositoryService: repositoryService)
                },
                saveWorkingTreeFile: { executionPath, filePath, content in
                    try repositoryService.saveLocalFileContent(at: executionPath, filePath: filePath, content: content)
                },
                stageWorkingTreePatch: { executionPath, patch in
                    try repositoryService.stagePatch(at: executionPath, patch: patch)
                },
                unstageWorkingTreePatch: { executionPath, patch in
                    try repositoryService.unstagePatch(at: executionPath, patch: patch)
                }
            )
        }
    }

    @ObservationIgnored private let client: Client
    @ObservationIgnored private let parser: @Sendable (String) -> WorkspaceDiffParsedDocument
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var loadRevision = 0
    @ObservationIgnored private let editableContentRebuildDelayNanoseconds: UInt64
    @ObservationIgnored private var editableContentRebuildTask: Task<Void, Never>?
    @ObservationIgnored private var editableContentRebuildRevision = 0
    @ObservationIgnored private var pendingSelectionPreference: DifferenceSelectionPreference?

    public var tab: WorkspaceDiffTabState
    public var documentState: WorkspaceDiffDocumentState
    public var sessionState: WorkspaceDiffSessionState
    public var selectedDifferenceAnchor: WorkspaceDiffDifferenceAnchor?
    public var viewerDescriptor: WorkspaceDiffViewerDescriptor?

    public init(
        tab: WorkspaceDiffTabState,
        client: Client,
        parser: @escaping @Sendable (String) -> WorkspaceDiffParsedDocument = WorkspaceDiffPatchParser.parse,
        editableContentRebuildDelayNanoseconds: UInt64 = 180_000_000
    ) {
        self.tab = tab
        self.client = client
        self.parser = parser
        self.editableContentRebuildDelayNanoseconds = editableContentRebuildDelayNanoseconds
        let initialRequestChain = tab.requestChain
            ?? WorkspaceDiffRequestChain(items: [makeRequestItem(from: tab)])
        self.sessionState = WorkspaceDiffSessionState(
            requestChain: initialRequestChain
        )
        self.selectedDifferenceAnchor = nil
        self.viewerDescriptor = nil
        self.documentState = WorkspaceDiffDocumentState(
            title: tab.title,
            viewerMode: tab.viewerMode
        )
    }

    deinit {
        loadTask?.cancel()
        editableContentRebuildTask?.cancel()
    }

    public func updateViewerMode(_ mode: WorkspaceDiffViewerMode) {
        guard documentState.viewerMode != mode else {
            return
        }
        tab.viewerMode = mode
        documentState.viewerMode = mode
        updateActiveRequestItemViewerMode(mode)
    }

    public func updateTab(_ tab: WorkspaceDiffTabState) {
        guard self.tab != tab else {
            return
        }

        let sourceChanged = self.tab.source != tab.source
        let titleChanged = documentState.title != tab.title
        let viewerModeChanged = documentState.viewerMode != tab.viewerMode
        self.tab = tab
        if titleChanged {
            documentState.title = tab.title
        }
        if viewerModeChanged {
            documentState.viewerMode = tab.viewerMode
        }

        sessionState = WorkspaceDiffSessionState(
            requestChain: tab.requestChain
                ?? WorkspaceDiffRequestChain(
                    items: [makeRequestItem(from: tab)]
                )
        )
        selectedDifferenceAnchor = nil
        pendingSelectionPreference = nil
        rebuildNavigatorState()

        guard sourceChanged else {
            return
        }

        cancelEditableContentRebuild()
        documentState.loadState = .idle
        refresh()
    }

    public func openSession(_ chain: WorkspaceDiffRequestChain) {
        cancelEditableContentRebuild()
        sessionState = WorkspaceDiffSessionState(requestChain: chain)
        tab.requestChain = chain
        selectedDifferenceAnchor = nil
        pendingSelectionPreference = .first
        rebuildNavigatorState()
        presentActiveRequestItem(refreshIfNeeded: true)
    }

    public func goToNextDifference() {
        guard sessionState.navigatorState.canGoNext else {
            return
        }

        let anchors = currentDifferenceAnchors
        if let currentAnchor = selectedDifferenceAnchor,
           let currentIndex = anchors.firstIndex(of: currentAnchor),
           currentIndex + 1 < anchors.count
        {
            selectedDifferenceAnchor = anchors[currentIndex + 1]
            rebuildNavigatorState()
            return
        }

        moveToRequestItem(at: sessionState.requestChain.activeIndex + 1, selectionPreference: .first)
    }

    public func goToPreviousDifference() {
        guard sessionState.navigatorState.canGoPrevious else {
            return
        }

        let anchors = currentDifferenceAnchors
        if let currentAnchor = selectedDifferenceAnchor,
           let currentIndex = anchors.firstIndex(of: currentAnchor),
           currentIndex > 0
        {
            selectedDifferenceAnchor = anchors[currentIndex - 1]
            rebuildNavigatorState()
            return
        }

        moveToRequestItem(at: sessionState.requestChain.activeIndex - 1, selectionPreference: .last)
    }

    public func updateEditableContent(_ text: String) {
        guard let rebuildRequest = applyEditableContentUpdate(text) else {
            return
        }
        scheduleEditableContentRebuild(for: rebuildRequest)
    }

    private func applyEditableContentUpdate(_ text: String) -> EditableContentRebuildRequest? {
        switch documentState.loadState {
        case let .loaded(.compare(document)):
            guard document.rightPane.isEditable, document.rightPane.text != text else {
                return nil
            }
            var rightPane = document.rightPane
            rightPane.text = text
            documentState.loadState = .loaded(
                .compare(
                    WorkspaceDiffCompareDocument(
                        mode: document.mode,
                        leftPane: document.leftPane,
                        rightPane: rightPane,
                        blocks: document.blocks
                    )
                )
            )
            return .compare(
                mode: document.mode,
                leftPane: document.leftPane,
                rightPane: rightPane
            )
        case let .loaded(.merge(document)):
            guard document.resultPane.isEditable, document.resultPane.text != text else {
                return nil
            }
            var resultPane = document.resultPane
            resultPane.text = text
            documentState.loadState = .loaded(
                .merge(
                    WorkspaceDiffMergeDocument(
                        oursPane: document.oursPane,
                        basePane: document.basePane,
                        theirsPane: document.theirsPane,
                        resultPane: resultPane,
                        conflictBlocks: document.conflictBlocks
                    )
                )
            )
            return .merge(
                oursPane: document.oursPane,
                basePane: document.basePane,
                theirsPane: document.theirsPane,
                resultPane: resultPane
            )
        default:
            return nil
        }
    }

    public func saveEditableContent() throws {
        guard case let .workingTreeChange(_, executionPath, filePath, _, _, _) = tab.source,
              let editableText = editableContentText
        else {
            return
        }
        try client.saveWorkingTreeFile(executionPath, filePath, editableText)
        refresh()
    }

    public func applyMergeAction(_ action: WorkspaceDiffMergeAction, blockID: String? = nil) {
        cancelEditableContentRebuild()
        guard case let .loaded(.merge(document)) = documentState.loadState else {
            return
        }

        var resultPane = document.resultPane
        if let blockID,
           let block = document.conflictBlocks.first(where: { $0.id == blockID })
        {
            let replacement = mergeReplacementText(for: action, block: block)
            resultPane.text = replaceText(
                in: document.resultPane.text,
                range: block.resultLineRange,
                replacement: replacement
            )
        } else {
            switch action {
            case .acceptOurs:
                resultPane.text = document.oursPane.text
            case .acceptTheirs:
                resultPane.text = document.theirsPane.text
            case .acceptBoth:
                resultPane.text = appendMergeTexts(document.oursPane.text, document.theirsPane.text)
            }
        }

        let updated = buildMergeDocument(
            oursPane: document.oursPane,
            basePane: document.basePane,
            theirsPane: document.theirsPane,
            resultPane: resultPane
        )
        applyLoadedDocument(.merge(updated))
    }

    public func applyCompareBlockAction(_ action: WorkspaceDiffCompareBlockAction, blockID: String) throws {
        cancelEditableContentRebuild()
        guard case let .loaded(.compare(document)) = documentState.loadState,
              let block = document.blocks.first(where: { $0.id == blockID }),
              case let .workingTreeChange(_, executionPath, filePath, _, _, _) = tab.source
        else {
            return
        }

        switch action {
        case .revert:
            guard document.rightPane.isEditable else {
                return
            }
            var rightPane = document.rightPane
            rightPane.text = replaceText(
                in: document.rightPane.text,
                range: block.rightLineRange,
                replacementLines: block.leftLines,
                replacementHasTrailingNewline: block.leftHasTrailingNewline
            )
            let updated = buildCompareDocument(
                mode: document.mode,
                leftPane: document.leftPane,
                rightPane: rightPane
            )
            applyLoadedDocument(.compare(updated))
        case .stage:
            guard document.mode == .unstaged || document.mode == .untracked else {
                return
            }
            try client.stageWorkingTreePatch(
                executionPath,
                buildCompareBlockPatch(filePath: filePath, block: block, mode: document.mode)
            )
            refresh()
        case .unstage:
            guard document.mode == .staged else {
                return
            }
            try client.unstageWorkingTreePatch(
                executionPath,
                buildCompareBlockPatch(filePath: filePath, block: block, mode: document.mode)
            )
            refresh()
        }
    }

    public var editableContentText: String? {
        switch documentState.loadState {
        case let .loaded(.compare(document)):
            return document.rightPane.isEditable ? document.rightPane.text : nil
        case let .loaded(.merge(document)):
            return document.resultPane.isEditable ? document.resultPane.text : nil
        default:
            return nil
        }
    }

    private var currentDifferenceAnchors: [WorkspaceDiffDifferenceAnchor] {
        switch documentState.loadState {
        case let .loaded(document):
            return differenceAnchors(for: document)
        default:
            return []
        }
    }

    public func refresh() {
        cancelEditableContentRebuild()
        loadTask?.cancel()
        loadRevision += 1
        let currentRevision = loadRevision
        documentState.loadState = .loading
        rebuildNavigatorState()

        let source = tab.source
        let parser = self.parser
        loadTask = Task { [client] in
            do {
                let document = try await Task.detached(priority: .userInitiated) {
                    switch source {
                    case let .gitLogCommitFile(repositoryPath, commitHash, filePath):
                        let diff = try client.loadGitLogCommitFileDiff(repositoryPath, commitHash, filePath)
                        return WorkspaceDiffLoadedDocument.patch(parser(diff))
                    case .workingTreeChange:
                        return normalizeLoadedDocument(try client.loadWorkingTreeDocument(source))
                    }
                }.value
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run { [weak self] in
                    guard let self, self.loadRevision == currentRevision else {
                        return
                    }
                    self.applyLoadedDocument(document)
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, self.loadRevision == currentRevision else {
                        return
                    }
                    self.selectedDifferenceAnchor = nil
                    self.pendingSelectionPreference = nil
                    self.documentState.loadState = .failed(
                        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    )
                    self.rebuildNavigatorState()
                }
            }
        }
    }

    private func cancelEditableContentRebuild() {
        editableContentRebuildTask?.cancel()
        editableContentRebuildTask = nil
        editableContentRebuildRevision += 1
    }

    private func scheduleEditableContentRebuild(
        for request: EditableContentRebuildRequest,
        delayNanoseconds: UInt64? = nil
    ) {
        editableContentRebuildTask?.cancel()
        editableContentRebuildRevision += 1
        let currentRevision = editableContentRebuildRevision
        let effectiveDelay = delayNanoseconds ?? editableContentRebuildDelayNanoseconds
        editableContentRebuildTask = Task { [weak self] in
            if effectiveDelay > 0 {
                try? await Task.sleep(nanoseconds: effectiveDelay)
            } else {
                await Task.yield()
            }
            guard !Task.isCancelled else {
                return
            }
            let document = await Task.detached(priority: .userInitiated) {
                request.buildDocument()
            }.value
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run { [weak self] in
                guard let self,
                      self.editableContentRebuildRevision == currentRevision
                else {
                    return
                }
                self.editableContentRebuildTask = nil
                self.applyLoadedDocument(document)
            }
        }
    }

    private func applyLoadedDocument(
        _ document: WorkspaceDiffLoadedDocument,
        selectionPreference: DifferenceSelectionPreference = .preserveCurrent
    ) {
        documentState.loadState = .loaded(document)
        let anchors = differenceAnchors(for: document)
        let resolvedPreference = pendingSelectionPreference ?? selectionPreference
        switch resolvedPreference {
        case .first:
            selectedDifferenceAnchor = anchors.first
        case .last:
            selectedDifferenceAnchor = anchors.last
        case .preserveCurrent:
            if let selectedDifferenceAnchor,
               anchors.contains(selectedDifferenceAnchor) {
                break
            }
            selectedDifferenceAnchor = anchors.first
        }
        pendingSelectionPreference = nil
        rebuildNavigatorState()
    }

    private func presentActiveRequestItem(refreshIfNeeded: Bool) {
        guard let item = sessionState.activeRequestItem else {
            selectedDifferenceAnchor = nil
            documentState.loadState = .idle
            rebuildNavigatorState()
            return
        }

        let sourceChanged = tab.source != item.source
        tab.title = item.title
        tab.source = item.source
        tab.viewerMode = item.preferredViewerMode
        documentState.title = item.title
        documentState.viewerMode = item.preferredViewerMode

        if refreshIfNeeded, (sourceChanged || !isCurrentDocumentLoaded(for: item.source)) {
            documentState.loadState = .idle
            refresh()
            return
        }

        if case let .loaded(document) = documentState.loadState {
            applyLoadedDocument(document)
        } else {
            rebuildNavigatorState()
        }
    }

    private func moveToRequestItem(
        at index: Int,
        selectionPreference: DifferenceSelectionPreference
    ) {
        guard sessionState.requestChain.items.indices.contains(index) else {
            return
        }
        sessionState.requestChain = sessionState.requestChain.updatingActiveIndex(index)
        tab.requestChain = sessionState.requestChain
        pendingSelectionPreference = selectionPreference
        selectedDifferenceAnchor = nil
        rebuildNavigatorState()
        presentActiveRequestItem(refreshIfNeeded: true)
    }

    private func rebuildNavigatorState() {
        let anchors = currentDifferenceAnchors
        let currentDifferenceIndex: Int
        if let selectedDifferenceAnchor,
           let index = anchors.firstIndex(of: selectedDifferenceAnchor) {
            currentDifferenceIndex = index + 1
        } else {
            currentDifferenceIndex = 0
        }

        sessionState.navigatorState = WorkspaceDiffNavigatorState(
            requestChain: sessionState.requestChain,
            currentDifferenceIndex: currentDifferenceIndex,
            totalDifferences: anchors.count
        )
        rebuildViewerDescriptor()
    }

    private func differenceAnchors(for document: WorkspaceDiffLoadedDocument) -> [WorkspaceDiffDifferenceAnchor] {
        switch document {
        case let .patch(parsed):
            return parsed.hunks.indices.map(WorkspaceDiffDifferenceAnchor.patchHunk)
        case let .compare(compare):
            return compare.blocks.map { .compareBlock($0.id) }
        case let .merge(merge):
            return merge.conflictBlocks.map { .mergeConflict($0.id) }
        }
    }

    private func isCurrentDocumentLoaded(for source: WorkspaceDiffSource) -> Bool {
        tab.source == source && {
            if case .loaded = documentState.loadState {
                return true
            }
            return false
        }()
    }

    private func updateActiveRequestItemViewerMode(_ mode: WorkspaceDiffViewerMode) {
        guard sessionState.requestChain.items.indices.contains(sessionState.requestChain.activeIndex) else {
            return
        }
        sessionState.requestChain.items[sessionState.requestChain.activeIndex].preferredViewerMode = mode
        rebuildNavigatorState()
    }

    private func rebuildViewerDescriptor() {
        guard case let .loaded(document) = documentState.loadState else {
            viewerDescriptor = nil
            return
        }

        viewerDescriptor = WorkspaceDiffViewerDescriptor(
            kind: viewerKind(for: document),
            navigatorState: sessionState.navigatorState,
            paneDescriptors: buildPaneDescriptors(for: document),
            selectedDifference: selectedDifferenceAnchor
        )
    }

    private func viewerKind(for document: WorkspaceDiffLoadedDocument) -> WorkspaceDiffViewerKind {
        switch document {
        case .patch:
            return .patch
        case .compare:
            return .twoSide
        case .merge:
            return .merge
        }
    }

    private func buildPaneDescriptors(for document: WorkspaceDiffLoadedDocument) -> [WorkspaceDiffPaneDescriptor] {
        let seeds = sessionState.activeRequestItem?.paneMetadataSeeds ?? []
        switch document {
        case let .patch(parsed):
            return [
                WorkspaceDiffPaneDescriptor(
                    role: .left,
                    metadata: makePaneMetadata(
                        role: .left,
                        fallbackTitle: "Before",
                        fallbackPath: parsed.oldPath ?? parsed.newPath,
                        fallbackOldPath: parsed.oldPath != parsed.newPath ? parsed.oldPath : nil,
                        seeds: seeds
                    )
                ),
                WorkspaceDiffPaneDescriptor(
                    role: .right,
                    metadata: makePaneMetadata(
                        role: .right,
                        fallbackTitle: "After",
                        fallbackPath: parsed.newPath ?? parsed.oldPath,
                        fallbackOldPath: parsed.oldPath != parsed.newPath ? parsed.oldPath : nil,
                        seeds: seeds
                    )
                ),
            ]
        case let .compare(compare):
            return [
                WorkspaceDiffPaneDescriptor(
                    role: .left,
                    metadata: makePaneMetadata(
                        role: .left,
                        fallbackTitle: compare.leftPane.title,
                        fallbackPath: compare.leftPane.path,
                        seeds: seeds
                    )
                ),
                WorkspaceDiffPaneDescriptor(
                    role: .right,
                    metadata: makePaneMetadata(
                        role: .right,
                        fallbackTitle: compare.rightPane.title,
                        fallbackPath: compare.rightPane.path,
                        seeds: seeds
                    )
                ),
            ]
        case let .merge(merge):
            return [
                WorkspaceDiffPaneDescriptor(
                    role: .ours,
                    metadata: makePaneMetadata(
                        role: .ours,
                        fallbackTitle: merge.oursPane.title,
                        fallbackPath: merge.oursPane.path,
                        seeds: seeds
                    )
                ),
                WorkspaceDiffPaneDescriptor(
                    role: .base,
                    metadata: makePaneMetadata(
                        role: .base,
                        fallbackTitle: merge.basePane.title,
                        fallbackPath: merge.basePane.path,
                        seeds: seeds
                    )
                ),
                WorkspaceDiffPaneDescriptor(
                    role: .theirs,
                    metadata: makePaneMetadata(
                        role: .theirs,
                        fallbackTitle: merge.theirsPane.title,
                        fallbackPath: merge.theirsPane.path,
                        seeds: seeds
                    )
                ),
                WorkspaceDiffPaneDescriptor(
                    role: .result,
                    metadata: makePaneMetadata(
                        role: .result,
                        fallbackTitle: merge.resultPane.title,
                        fallbackPath: merge.resultPane.path,
                        seeds: seeds
                    )
                ),
            ]
        }
    }

    private func makePaneMetadata(
        role: WorkspaceDiffPaneHeaderRole,
        fallbackTitle: String,
        fallbackPath: String?,
        fallbackOldPath: String? = nil,
        seeds: [WorkspaceDiffPaneMetadataSeed]
    ) -> WorkspaceDiffPaneMetadata {
        let seed = seeds.first(where: { $0.role == role })
        return WorkspaceDiffPaneMetadata(
            title: seed?.title ?? fallbackTitle,
            path: seed?.path ?? fallbackPath,
            oldPath: seed?.oldPath ?? fallbackOldPath,
            revision: seed?.revision,
            hash: seed?.hash,
            author: seed?.author,
            timestamp: seed?.timestamp,
            tooltip: seed?.tooltip,
            copyPayloads: seed?.copyPayloads ?? []
        )
    }
}

private func makeRequestItem(from tab: WorkspaceDiffTabState) -> WorkspaceDiffRequestItem {
    WorkspaceDiffRequestItem(
        id: tab.identity,
        title: tab.title,
        source: tab.source,
        preferredViewerMode: tab.viewerMode
    )
}

private func buildWorkingTreeDocument(
    for source: WorkspaceDiffSource,
    repositoryService: NativeGitRepositoryService
) throws -> WorkspaceDiffLoadedDocument {
    guard case let .workingTreeChange(repositoryPath, executionPath, filePath, group, _, _) = source else {
        throw WorkspaceGitCommandError.parseFailure("working tree source 类型不匹配")
    }

    switch group {
    case .staged:
        return .compare(
            buildCompareDocument(
                mode: .staged,
                leftPane: WorkspaceDiffEditorPane(
                    title: "HEAD",
                    path: filePath,
                    text: try repositoryService.loadHeadFileContent(at: repositoryPath, filePath: filePath),
                    isEditable: false
                ),
                rightPane: WorkspaceDiffEditorPane(
                    title: "Staged",
                    path: filePath,
                    text: try repositoryService.loadIndexFileContent(at: executionPath, filePath: filePath),
                    isEditable: false
                )
            )
        )
    case .conflicted:
        let contents = try repositoryService.loadConflictFileContents(at: executionPath, filePath: filePath)
        return .merge(
            buildMergeDocument(
                oursPane: WorkspaceDiffEditorPane(title: "Ours", path: filePath, text: contents.ours, isEditable: false),
                basePane: WorkspaceDiffEditorPane(title: "Base", path: filePath, text: contents.base, isEditable: false),
                theirsPane: WorkspaceDiffEditorPane(title: "Theirs", path: filePath, text: contents.theirs, isEditable: false),
                resultPane: WorkspaceDiffEditorPane(title: "Result", path: filePath, text: contents.result, isEditable: true)
            )
        )
    case .untracked:
        return .compare(
            buildCompareDocument(
                mode: .untracked,
                leftPane: WorkspaceDiffEditorPane(title: "Empty", path: nil, text: "", isEditable: false),
                rightPane: WorkspaceDiffEditorPane(
                    title: "Local",
                    path: filePath,
                    text: try repositoryService.loadLocalFileContent(at: executionPath, filePath: filePath),
                    isEditable: true
                )
            )
        )
    case .unstaged, .none:
        return .compare(
            buildCompareDocument(
                mode: .unstaged,
                leftPane: WorkspaceDiffEditorPane(
                    title: "Staged",
                    path: filePath,
                    text: try repositoryService.loadIndexFileContent(at: executionPath, filePath: filePath),
                    isEditable: false
                ),
                rightPane: WorkspaceDiffEditorPane(
                    title: "Local",
                    path: filePath,
                    text: try repositoryService.loadLocalFileContent(at: executionPath, filePath: filePath),
                    isEditable: true
                )
            )
        )
    }
}

private func normalizeLoadedDocument(_ document: WorkspaceDiffLoadedDocument) -> WorkspaceDiffLoadedDocument {
    switch document {
    case let .patch(parsed):
        return .patch(parsed)
    case let .compare(compare):
        return .compare(
            buildCompareDocument(
                mode: compare.mode,
                leftPane: compare.leftPane,
                rightPane: compare.rightPane
            )
        )
    case let .merge(merge):
        return .merge(
            buildMergeDocument(
                oursPane: merge.oursPane,
                basePane: merge.basePane,
                theirsPane: merge.theirsPane,
                resultPane: merge.resultPane
            )
        )
    }
}

private func buildCompareDocument(
    mode: WorkspaceDiffCompareMode,
    leftPane: WorkspaceDiffEditorPane,
    rightPane: WorkspaceDiffEditorPane
) -> WorkspaceDiffCompareDocument {
    let comparison = buildCompareBlocks(leftText: leftPane.text, rightText: rightPane.text)
    var updatedLeftPane = leftPane
    updatedLeftPane.highlights = comparison.leftHighlights
    updatedLeftPane.inlineHighlights = comparison.leftInlineHighlights
    var updatedRightPane = rightPane
    updatedRightPane.highlights = comparison.rightHighlights
    updatedRightPane.inlineHighlights = comparison.rightInlineHighlights
    return WorkspaceDiffCompareDocument(
        mode: mode,
        leftPane: updatedLeftPane,
        rightPane: updatedRightPane,
        blocks: comparison.blocks
    )
}

private func buildMergeDocument(
    oursPane: WorkspaceDiffEditorPane,
    basePane: WorkspaceDiffEditorPane,
    theirsPane: WorkspaceDiffEditorPane,
    resultPane: WorkspaceDiffEditorPane
) -> WorkspaceDiffMergeDocument {
    let conflicts = buildMergeConflictBlocks(
        oursText: oursPane.text,
        theirsText: theirsPane.text,
        resultText: resultPane.text
    )
    let mergeInlineHighlights = buildMergeInlineHighlights(from: conflicts.blocks)
    var updatedOursPane = oursPane
    updatedOursPane.highlights = conflicts.oursHighlights
    updatedOursPane.inlineHighlights = mergeInlineHighlights.oursHighlights
    var updatedBasePane = basePane
    updatedBasePane.highlights = []
    updatedBasePane.inlineHighlights = []
    var updatedTheirsPane = theirsPane
    updatedTheirsPane.highlights = conflicts.theirsHighlights
    updatedTheirsPane.inlineHighlights = mergeInlineHighlights.theirsHighlights
    var updatedResultPane = resultPane
    updatedResultPane.highlights = conflicts.resultHighlights
    updatedResultPane.inlineHighlights = mergeInlineHighlights.resultHighlights
    return WorkspaceDiffMergeDocument(
        oursPane: updatedOursPane,
        basePane: updatedBasePane,
        theirsPane: updatedTheirsPane,
        resultPane: updatedResultPane,
        conflictBlocks: conflicts.blocks
    )
}

private struct CompareBuildResult {
    var blocks: [WorkspaceDiffCompareBlock]
    var leftHighlights: [WorkspaceDiffEditorHighlight]
    var rightHighlights: [WorkspaceDiffEditorHighlight]
    var leftInlineHighlights: [WorkspaceDiffEditorInlineHighlight]
    var rightInlineHighlights: [WorkspaceDiffEditorInlineHighlight]
}

private func buildCompareBlocks(leftText: String, rightText: String) -> CompareBuildResult {
    let leftBuffer = TextLineBuffer(text: leftText)
    let rightBuffer = TextLineBuffer(text: rightText)
    guard leftBuffer.text() != rightBuffer.text() else {
        return CompareBuildResult(
            blocks: [],
            leftHighlights: [],
            rightHighlights: [],
            leftInlineHighlights: [],
            rightInlineHighlights: []
        )
    }

    let leftCount = leftBuffer.lines.count
    let rightCount = rightBuffer.lines.count
    let complexityTooHigh = rightCount > 0 && leftCount > 180_000 / max(1, rightCount)
    if complexityTooHigh {
        let wholeBlock = makeCompareBlock(
            index: 0,
            leftRange: WorkspaceDiffLineRange(startLine: 0, lineCount: leftCount),
            rightRange: WorkspaceDiffLineRange(startLine: 0, lineCount: rightCount),
            leftBuffer: leftBuffer,
            rightBuffer: rightBuffer
        )
        return CompareBuildResult(
            blocks: [wholeBlock],
            leftHighlights: highlightEntries(for: [wholeBlock], side: .left),
            rightHighlights: highlightEntries(for: [wholeBlock], side: .right),
            leftInlineHighlights: buildInlineHighlights(for: [wholeBlock], side: .left),
            rightInlineHighlights: buildInlineHighlights(for: [wholeBlock], side: .right)
        )
    }

    var lcs = Array(
        repeating: Array(repeating: 0, count: rightCount + 1),
        count: leftCount + 1
    )
    if leftCount > 0, rightCount > 0 {
        for leftIndex in stride(from: leftCount - 1, through: 0, by: -1) {
            for rightIndex in stride(from: rightCount - 1, through: 0, by: -1) {
                if leftBuffer.lines[leftIndex] == rightBuffer.lines[rightIndex] {
                    lcs[leftIndex][rightIndex] = lcs[leftIndex + 1][rightIndex + 1] + 1
                } else {
                    lcs[leftIndex][rightIndex] = max(lcs[leftIndex + 1][rightIndex], lcs[leftIndex][rightIndex + 1])
                }
            }
        }
    }

    var blocks = [WorkspaceDiffCompareBlock]()
    var currentLeftStart: Int?
    var currentRightStart: Int?
    var leftIndex = 0
    var rightIndex = 0

    func flushBlock(endLeftIndex: Int, endRightIndex: Int) {
        guard let currentLeftStart, let currentRightStart,
              currentLeftStart != endLeftIndex || currentRightStart != endRightIndex
        else {
            return
        }
        blocks.append(
            makeCompareBlock(
                index: blocks.count,
                leftRange: WorkspaceDiffLineRange(startLine: currentLeftStart, lineCount: endLeftIndex - currentLeftStart),
                rightRange: WorkspaceDiffLineRange(startLine: currentRightStart, lineCount: endRightIndex - currentRightStart),
                leftBuffer: leftBuffer,
                rightBuffer: rightBuffer
            )
        )
    }

    while leftIndex < leftCount || rightIndex < rightCount {
        if leftIndex < leftCount,
           rightIndex < rightCount,
           leftBuffer.lines[leftIndex] == rightBuffer.lines[rightIndex]
        {
            flushBlock(endLeftIndex: leftIndex, endRightIndex: rightIndex)
            currentLeftStart = nil
            currentRightStart = nil
            leftIndex += 1
            rightIndex += 1
            continue
        }

        if currentLeftStart == nil {
            currentLeftStart = leftIndex
            currentRightStart = rightIndex
        }

        let shouldInsert = rightIndex < rightCount
            && (leftIndex == leftCount || lcs[leftIndex][rightIndex + 1] >= lcs[leftIndex + 1][rightIndex])
        if shouldInsert {
            rightIndex += 1
        } else if leftIndex < leftCount {
            leftIndex += 1
        }
    }

    flushBlock(endLeftIndex: leftIndex, endRightIndex: rightIndex)
    return CompareBuildResult(
        blocks: blocks,
        leftHighlights: highlightEntries(for: blocks, side: .left),
        rightHighlights: highlightEntries(for: blocks, side: .right),
        leftInlineHighlights: buildInlineHighlights(for: blocks, side: .left),
        rightInlineHighlights: buildInlineHighlights(for: blocks, side: .right)
    )
}

private enum CompareHighlightSide {
    case left
    case right
}

private func highlightEntries(
    for blocks: [WorkspaceDiffCompareBlock],
    side: CompareHighlightSide
) -> [WorkspaceDiffEditorHighlight] {
    blocks.compactMap { block in
        switch side {
        case .left:
            guard block.leftLineRange.lineCount > 0 else {
                return nil
            }
            let kind: WorkspaceDiffEditorHighlightKind = block.rightLineRange.lineCount > 0 ? .changed : .removed
            return WorkspaceDiffEditorHighlight(kind: kind, lineRange: block.leftLineRange)
        case .right:
            guard block.rightLineRange.lineCount > 0 else {
                return nil
            }
            let kind: WorkspaceDiffEditorHighlightKind = block.leftLineRange.lineCount > 0 ? .changed : .added
            return WorkspaceDiffEditorHighlight(kind: kind, lineRange: block.rightLineRange)
        }
    }
}

private func buildInlineHighlights(
    for blocks: [WorkspaceDiffCompareBlock],
    side: CompareHighlightSide
) -> [WorkspaceDiffEditorInlineHighlight] {
    var highlights = [WorkspaceDiffEditorInlineHighlight]()
    for block in blocks {
        guard block.leftLineRange.lineCount == block.rightLineRange.lineCount,
              block.leftLineRange.lineCount > 0,
              block.rightLineRange.lineCount > 0
        else {
            continue
        }

        for offset in 0..<block.leftLineRange.lineCount {
            let leftLine = block.leftLines[offset]
            let rightLine = block.rightLines[offset]
            guard leftLine != rightLine else {
                continue
            }
            let (leftRange, rightRange) = inlineDiffRanges(left: leftLine, right: rightLine)
            switch side {
            case .left:
                guard leftRange.length > 0 else {
                    continue
                }
                highlights.append(
                    WorkspaceDiffEditorInlineHighlight(
                        kind: .changed,
                        lineIndex: block.leftLineRange.startLine + offset,
                        range: leftRange
                    )
                )
            case .right:
                guard rightRange.length > 0 else {
                    continue
                }
                highlights.append(
                    WorkspaceDiffEditorInlineHighlight(
                        kind: .changed,
                        lineIndex: block.rightLineRange.startLine + offset,
                        range: rightRange
                    )
                )
            }
        }
    }
    return highlights
}

private func inlineDiffRanges(
    left: String,
    right: String
) -> (WorkspaceDiffInlineRange, WorkspaceDiffInlineRange) {
    let leftNSString = left as NSString
    let rightNSString = right as NSString
    let minLength = min(leftNSString.length, rightNSString.length)

    var prefixLength = 0
    while prefixLength < minLength,
          leftNSString.character(at: prefixLength) == rightNSString.character(at: prefixLength)
    {
        prefixLength += 1
    }

    var leftEnd = leftNSString.length
    var rightEnd = rightNSString.length
    while leftEnd > prefixLength,
          rightEnd > prefixLength,
          leftNSString.character(at: leftEnd - 1) == rightNSString.character(at: rightEnd - 1)
    {
        leftEnd -= 1
        rightEnd -= 1
    }

    return (
        WorkspaceDiffInlineRange(startColumn: prefixLength, length: max(0, leftEnd - prefixLength)),
        WorkspaceDiffInlineRange(startColumn: prefixLength, length: max(0, rightEnd - prefixLength))
    )
}

private func makeCompareBlock(
    index: Int,
    leftRange: WorkspaceDiffLineRange,
    rightRange: WorkspaceDiffLineRange,
    leftBuffer: TextLineBuffer,
    rightBuffer: TextLineBuffer
) -> WorkspaceDiffCompareBlock {
    let leftSlice = leftBuffer.slice(range: leftRange)
    let rightSlice = rightBuffer.slice(range: rightRange)
    return WorkspaceDiffCompareBlock(
        id: "compare-block-\(index)",
        summary: compareSummary(leftRange: leftRange, rightRange: rightRange),
        leftLineRange: leftRange,
        rightLineRange: rightRange,
        leftLines: leftSlice.lines,
        rightLines: rightSlice.lines,
        leftHasTrailingNewline: leftSlice.endsWithTrailingNewline,
        rightHasTrailingNewline: rightSlice.endsWithTrailingNewline
    )
}

private func compareSummary(
    leftRange: WorkspaceDiffLineRange,
    rightRange: WorkspaceDiffLineRange
) -> String {
    let leftText = leftRange.lineCount == 0 ? "左 ∅" : "左 \(leftRange.displayText)"
    let rightText = rightRange.lineCount == 0 ? "右 ∅" : "右 \(rightRange.displayText)"
    return "\(leftText) · \(rightText)"
}

private struct MergeConflictBuildResult {
    var blocks: [WorkspaceDiffMergeConflictBlock]
    var oursHighlights: [WorkspaceDiffEditorHighlight]
    var theirsHighlights: [WorkspaceDiffEditorHighlight]
    var resultHighlights: [WorkspaceDiffEditorHighlight]
}

private struct MergeInlineHighlightBuildResult {
    var oursHighlights: [WorkspaceDiffEditorInlineHighlight]
    var theirsHighlights: [WorkspaceDiffEditorInlineHighlight]
    var resultHighlights: [WorkspaceDiffEditorInlineHighlight]
}

private func buildMergeConflictBlocks(
    oursText: String,
    theirsText: String,
    resultText: String
) -> MergeConflictBuildResult {
    let oursBuffer = TextLineBuffer(text: oursText)
    let theirsBuffer = TextLineBuffer(text: theirsText)
    let resultBuffer = TextLineBuffer(text: resultText)

    var blocks = [WorkspaceDiffMergeConflictBlock]()
    var oursHighlights = [WorkspaceDiffEditorHighlight]()
    var theirsHighlights = [WorkspaceDiffEditorHighlight]()
    var resultHighlights = [WorkspaceDiffEditorHighlight]()
    var oursSearchStart = 0
    var theirsSearchStart = 0
    var lineIndex = 0

    while lineIndex < resultBuffer.lines.count {
        guard resultBuffer.lines[lineIndex].hasPrefix("<<<<<<<") else {
            lineIndex += 1
            continue
        }

        let blockStart = lineIndex
        lineIndex += 1
        var oursLines = [String]()
        while lineIndex < resultBuffer.lines.count,
              !resultBuffer.lines[lineIndex].hasPrefix("=======")
        {
            oursLines.append(resultBuffer.lines[lineIndex])
            lineIndex += 1
        }
        guard lineIndex < resultBuffer.lines.count else {
            break
        }

        lineIndex += 1
        var theirsLines = [String]()
        while lineIndex < resultBuffer.lines.count,
              !resultBuffer.lines[lineIndex].hasPrefix(">>>>>>>")
        {
            theirsLines.append(resultBuffer.lines[lineIndex])
            lineIndex += 1
        }
        guard lineIndex < resultBuffer.lines.count else {
            break
        }

        let blockEnd = lineIndex
        lineIndex += 1

        let oursRange = findSequenceRange(
            needle: oursLines,
            in: oursBuffer.lines,
            startingAt: &oursSearchStart
        )
        let theirsRange = findSequenceRange(
            needle: theirsLines,
            in: theirsBuffer.lines,
            startingAt: &theirsSearchStart
        )
        let resultRange = WorkspaceDiffLineRange(startLine: blockStart, lineCount: blockEnd - blockStart + 1)
        let resultOursRange = WorkspaceDiffLineRange(startLine: blockStart + 1, lineCount: oursLines.count)
        let resultTheirsRange = WorkspaceDiffLineRange(
            startLine: blockStart + oursLines.count + 2,
            lineCount: theirsLines.count
        )
        let block = WorkspaceDiffMergeConflictBlock(
            id: "merge-conflict-\(blocks.count)",
            summary: "冲突块 \(blocks.count + 1) · Result \(resultRange.displayText)",
            resultLineRange: resultRange,
            resultOursLineRange: oursLines.isEmpty ? nil : resultOursRange,
            resultTheirsLineRange: theirsLines.isEmpty ? nil : resultTheirsRange,
            oursLineRange: oursRange,
            theirsLineRange: theirsRange,
            oursText: TextLineBuffer(lines: oursLines, endsWithTrailingNewline: !oursLines.isEmpty).text(),
            theirsText: TextLineBuffer(lines: theirsLines, endsWithTrailingNewline: !theirsLines.isEmpty).text(),
            baseText: nil
        )
        blocks.append(block)
        resultHighlights.append(.init(kind: .conflict, lineRange: resultRange))
        if let oursRange {
            oursHighlights.append(.init(kind: .conflict, lineRange: oursRange))
        }
        if let theirsRange {
            theirsHighlights.append(.init(kind: .conflict, lineRange: theirsRange))
        }
    }

    return MergeConflictBuildResult(
        blocks: blocks,
        oursHighlights: oursHighlights,
        theirsHighlights: theirsHighlights,
        resultHighlights: resultHighlights
    )
}

private func buildMergeInlineHighlights(
    from blocks: [WorkspaceDiffMergeConflictBlock]
) -> MergeInlineHighlightBuildResult {
    var oursHighlights = [WorkspaceDiffEditorInlineHighlight]()
    var theirsHighlights = [WorkspaceDiffEditorInlineHighlight]()
    var resultHighlights = [WorkspaceDiffEditorInlineHighlight]()

    for block in blocks {
        guard let oursLineRange = block.oursLineRange,
              let theirsLineRange = block.theirsLineRange,
              let resultOursLineRange = block.resultOursLineRange,
              let resultTheirsLineRange = block.resultTheirsLineRange,
              oursLineRange.lineCount == theirsLineRange.lineCount,
              oursLineRange.lineCount == resultOursLineRange.lineCount,
              theirsLineRange.lineCount == resultTheirsLineRange.lineCount,
              oursLineRange.lineCount > 0
        else {
            continue
        }

        let oursLines = splitLinesPreservingContent(block.oursText)
        let theirsLines = splitLinesPreservingContent(block.theirsText)
        guard oursLines.count == theirsLines.count else {
            continue
        }

        for offset in 0..<min(oursLines.count, theirsLines.count) {
            guard oursLines[offset] != theirsLines[offset] else {
                continue
            }
            let (oursRange, theirsRange) = inlineDiffRanges(left: oursLines[offset], right: theirsLines[offset])
            if oursRange.length > 0 {
                oursHighlights.append(
                    WorkspaceDiffEditorInlineHighlight(
                        kind: .conflict,
                        lineIndex: oursLineRange.startLine + offset,
                        range: oursRange
                    )
                )
                resultHighlights.append(
                    WorkspaceDiffEditorInlineHighlight(
                        kind: .conflict,
                        lineIndex: resultOursLineRange.startLine + offset,
                        range: oursRange
                    )
                )
            }
            if theirsRange.length > 0 {
                theirsHighlights.append(
                    WorkspaceDiffEditorInlineHighlight(
                        kind: .conflict,
                        lineIndex: theirsLineRange.startLine + offset,
                        range: theirsRange
                    )
                )
                resultHighlights.append(
                    WorkspaceDiffEditorInlineHighlight(
                        kind: .conflict,
                        lineIndex: resultTheirsLineRange.startLine + offset,
                        range: theirsRange
                    )
                )
            }
        }
    }

    return MergeInlineHighlightBuildResult(
        oursHighlights: oursHighlights,
        theirsHighlights: theirsHighlights,
        resultHighlights: resultHighlights
    )
}

private func splitLinesPreservingContent(_ text: String) -> [String] {
    let buffer = TextLineBuffer(text: text)
    return buffer.lines
}

private func findSequenceRange(
    needle: [String],
    in haystack: [String],
    startingAt start: inout Int
) -> WorkspaceDiffLineRange? {
    guard !needle.isEmpty, haystack.count >= needle.count else {
        return nil
    }

    if start < 0 {
        start = 0
    }
    if start > haystack.count - needle.count {
        start = max(0, haystack.count - needle.count)
    }

    for index in start...(haystack.count - needle.count) {
        if Array(haystack[index..<(index + needle.count)]) == needle {
            start = index + needle.count
            return WorkspaceDiffLineRange(startLine: index, lineCount: needle.count)
        }
    }
    return nil
}

private func mergeReplacementText(
    for action: WorkspaceDiffMergeAction,
    block: WorkspaceDiffMergeConflictBlock
) -> String {
    switch action {
    case .acceptOurs:
        return block.oursText
    case .acceptTheirs:
        return block.theirsText
    case .acceptBoth:
        return appendMergeTexts(block.oursText, block.theirsText)
    }
}

private func appendMergeTexts(_ lhs: String, _ rhs: String) -> String {
    guard !lhs.isEmpty else {
        return rhs
    }
    guard !rhs.isEmpty else {
        return lhs
    }
    if lhs.hasSuffix("\n") || rhs.hasPrefix("\n") {
        return lhs + rhs
    }
    return lhs + "\n" + rhs
}

private func buildCompareBlockPatch(
    filePath: String,
    block: WorkspaceDiffCompareBlock,
    mode: WorkspaceDiffCompareMode
) -> String {
    let oldStart = diffHeaderStart(for: block.leftLineRange)
    let newStart = diffHeaderStart(for: block.rightLineRange)
    let patchKind = compareBlockPatchKind(block: block, mode: mode)
    var lines = ["diff --git a/\(filePath) b/\(filePath)"]
    switch patchKind {
    case .modified:
        lines.append("--- a/\(filePath)")
        lines.append("+++ b/\(filePath)")
    case .newFile:
        lines.append("new file mode 100644")
        lines.append("--- /dev/null")
        lines.append("+++ b/\(filePath)")
    case .deletedFile:
        lines.append("deleted file mode 100644")
        lines.append("--- a/\(filePath)")
        lines.append("+++ /dev/null")
    }
    lines.append("@@ -\(oldStart),\(block.leftLineRange.lineCount) +\(newStart),\(block.rightLineRange.lineCount) @@")
    lines.append(contentsOf: block.leftLines.map { "-\($0)" })
    lines.append(contentsOf: block.rightLines.map { "+\($0)" })
    return lines.joined(separator: "\n") + "\n"
}

private enum CompareBlockPatchKind {
    case modified
    case newFile
    case deletedFile
}

private func compareBlockPatchKind(
    block: WorkspaceDiffCompareBlock,
    mode: WorkspaceDiffCompareMode
) -> CompareBlockPatchKind {
    if mode == .untracked || (block.leftLineRange.lineCount == 0 && block.rightLineRange.lineCount > 0) {
        return .newFile
    }
    if block.leftLineRange.lineCount > 0, block.rightLineRange.lineCount == 0 {
        return .deletedFile
    }
    return .modified
}

private func diffHeaderStart(for range: WorkspaceDiffLineRange) -> Int {
    range.lineCount == 0 ? range.startLine : range.startLine + 1
}

private func replaceText(
    in text: String,
    range: WorkspaceDiffLineRange,
    replacement: String
) -> String {
    let replacementBuffer = TextLineBuffer(text: replacement)
    return replaceText(
        in: text,
        range: range,
        replacementLines: replacementBuffer.lines,
        replacementHasTrailingNewline: replacementBuffer.endsWithTrailingNewline
    )
}

private func replaceText(
    in text: String,
    range: WorkspaceDiffLineRange,
    replacementLines: [String],
    replacementHasTrailingNewline: Bool
) -> String {
    let buffer = TextLineBuffer(text: text)
    return buffer
        .replacing(
            range: range,
            with: TextLineBuffer(lines: replacementLines, endsWithTrailingNewline: replacementHasTrailingNewline)
        )
        .text()
}

private struct TextLineBuffer {
    var lines: [String]
    var endsWithTrailingNewline: Bool

    init(text: String) {
        self.endsWithTrailingNewline = text.hasSuffix("\n")
        self.lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if endsWithTrailingNewline, lines.last == "" {
            lines.removeLast()
        }
    }

    init(lines: [String], endsWithTrailingNewline: Bool) {
        self.lines = lines
        self.endsWithTrailingNewline = endsWithTrailingNewline
    }

    func text() -> String {
        guard !lines.isEmpty else {
            return endsWithTrailingNewline ? "\n" : ""
        }
        let joined = lines.joined(separator: "\n")
        return endsWithTrailingNewline ? joined + "\n" : joined
    }

    func slice(range: WorkspaceDiffLineRange) -> TextLineBuffer {
        let safeStart = min(max(0, range.startLine), lines.count)
        let safeEnd = min(max(safeStart, range.endLine), lines.count)
        return TextLineBuffer(
            lines: Array(lines[safeStart..<safeEnd]),
            endsWithTrailingNewline: safeEnd == lines.count ? endsWithTrailingNewline : false
        )
    }

    func replacing(range: WorkspaceDiffLineRange, with replacement: TextLineBuffer) -> TextLineBuffer {
        let safeStart = min(max(0, range.startLine), lines.count)
        let safeEnd = min(max(safeStart, range.endLine), lines.count)
        var updatedLines = lines
        updatedLines.replaceSubrange(safeStart..<safeEnd, with: replacement.lines)
        let touchesEnd = safeEnd == lines.count
        let updatedTrailingNewline = touchesEnd ? replacement.endsWithTrailingNewline : endsWithTrailingNewline
        return TextLineBuffer(lines: updatedLines, endsWithTrailingNewline: updatedTrailingNewline)
    }
}
