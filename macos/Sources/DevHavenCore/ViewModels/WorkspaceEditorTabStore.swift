import Foundation

@MainActor
final class WorkspaceEditorTabStore {
    struct OpenResult {
        var tabs: [WorkspaceEditorTabState]
        var openedTabID: String
        var resetRuntimeSession: Bool
        var assignToActiveGroup: Bool
    }

    struct MutationResult {
        var tabs: [WorkspaceEditorTabState]
        var didMutate: Bool
    }

    private let normalizePath: @MainActor (String) -> String
    private let makeTabID: @MainActor () -> String

    init(
        normalizePath: @escaping @MainActor (String) -> String,
        makeTabID: @escaping @MainActor () -> String = {
            "workspace-editor:\(UUID().uuidString.lowercased())"
        }
    ) {
        self.normalizePath = normalizePath
        self.makeTabID = makeTabID
    }

    func reopenExistingTab(
        filePath: String,
        openingPolicy: WorkspaceEditorTabOpeningPolicy,
        in tabs: [WorkspaceEditorTabState]
    ) -> OpenResult? {
        let normalizedFilePath = normalizePath(filePath)
        guard let existingIndex = tabs.firstIndex(where: {
            normalizePath($0.filePath) == normalizedFilePath
        }) else {
            return nil
        }

        var nextTabs = tabs
        let existingTabID = nextTabs[existingIndex].id
        var existingTab = nextTabs.remove(at: existingIndex)
        let previousPinnedState = existingTab.isPinned
        applyOpeningPolicy(openingPolicy, to: &existingTab)
        reinsertTab(
            existingTab,
            into: &nextTabs,
            preferredIndex: previousPinnedState == existingTab.isPinned ? existingIndex : nil
        )
        return OpenResult(
            tabs: nextTabs,
            openedTabID: existingTabID,
            resetRuntimeSession: false,
            assignToActiveGroup: openingPolicy == .preview && !existingTab.isPinned
        )
    }

    func openNewTab(
        projectPath: String,
        filePath: String,
        document: WorkspaceEditorDocumentSnapshot,
        openingPolicy: WorkspaceEditorTabOpeningPolicy,
        in tabs: [WorkspaceEditorTabState]
    ) -> OpenResult {
        var nextTabs = tabs
        let reusedPreviewIndex = openingPolicy == .preview
            ? nextTabs.firstIndex(where: { $0.isPreview && !$0.isPinned })
            : nil
        let tabID = reusedPreviewIndex.flatMap { nextTabs.indices.contains($0) ? nextTabs[$0].id : nil }
            ?? makeTabID()
        let tab = makeTabState(
            tabID: tabID,
            projectPath: projectPath,
            filePath: filePath,
            document: document,
            openingPolicy: openingPolicy
        )

        if let reusedPreviewIndex {
            nextTabs[reusedPreviewIndex] = tab
        } else {
            reinsertTab(tab, into: &nextTabs)
        }

        return OpenResult(
            tabs: nextTabs,
            openedTabID: tab.id,
            resetRuntimeSession: reusedPreviewIndex != nil,
            assignToActiveGroup: true
        )
    }

    func promotePreviewTabToRegular(
        _ tabID: String,
        in tabs: [WorkspaceEditorTabState]
    ) -> MutationResult {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              tabs[index].isPreview
        else {
            return MutationResult(tabs: tabs, didMutate: false)
        }

        var nextTabs = tabs
        nextTabs[index].isPreview = false
        return MutationResult(tabs: nextTabs, didMutate: true)
    }

    func insertRestoredTab(
        _ tab: WorkspaceEditorTabState,
        in tabs: [WorkspaceEditorTabState]
    ) -> [WorkspaceEditorTabState] {
        var nextTabs = tabs
        reinsertTab(tab, into: &nextTabs)
        return nextTabs
    }

    func setTabPinned(
        _ isPinned: Bool,
        tabID: String,
        in tabs: [WorkspaceEditorTabState]
    ) -> MutationResult {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else {
            return MutationResult(tabs: tabs, didMutate: false)
        }

        var nextTabs = tabs
        var tab = nextTabs.remove(at: index)
        let previousPinnedState = tab.isPinned
        let previousPreviewState = tab.isPreview

        tab.isPinned = isPinned
        if isPinned {
            tab.isPreview = false
        }

        guard previousPinnedState != tab.isPinned || previousPreviewState != tab.isPreview else {
            nextTabs.insert(tab, at: min(index, nextTabs.count))
            return MutationResult(tabs: nextTabs, didMutate: false)
        }

        let preferredIndex: Int? = isPinned ? nil : firstUnpinnedTabInsertionIndex(in: nextTabs)
        reinsertTab(tab, into: &nextTabs, preferredIndex: preferredIndex)
        return MutationResult(tabs: nextTabs, didMutate: true)
    }

    private func makeTabState(
        tabID: String,
        projectPath: String,
        filePath: String,
        document: WorkspaceEditorDocumentSnapshot,
        openingPolicy: WorkspaceEditorTabOpeningPolicy
    ) -> WorkspaceEditorTabState {
        WorkspaceEditorTabState(
            id: tabID,
            identity: filePath,
            projectPath: projectPath,
            filePath: filePath,
            title: URL(fileURLWithPath: filePath).lastPathComponent,
            isPinned: openingPolicy == .pinned,
            isPreview: openingPolicy == .preview,
            kind: document.kind,
            text: document.text,
            isEditable: document.isEditable,
            externalChangeState: .inSync,
            message: document.message,
            lastLoadedModificationDate: document.modificationDate,
            savedContentFingerprint: document.contentFingerprint
        )
    }

    private func applyOpeningPolicy(
        _ openingPolicy: WorkspaceEditorTabOpeningPolicy,
        to tab: inout WorkspaceEditorTabState
    ) {
        switch openingPolicy {
        case .preview:
            break
        case .regular:
            tab.isPreview = false
        case .pinned:
            tab.isPinned = true
            tab.isPreview = false
        }
    }

    private func reinsertTab(
        _ tab: WorkspaceEditorTabState,
        into tabs: inout [WorkspaceEditorTabState],
        preferredIndex: Int? = nil
    ) {
        if tab.isPinned {
            tabs.insert(tab, at: pinnedTabInsertionIndex(in: tabs))
            return
        }

        if let preferredIndex {
            let clampedIndex = min(max(preferredIndex, firstUnpinnedTabInsertionIndex(in: tabs)), tabs.count)
            tabs.insert(tab, at: clampedIndex)
            return
        }

        tabs.append(tab)
    }

    private func pinnedTabInsertionIndex(in tabs: [WorkspaceEditorTabState]) -> Int {
        tabs.lastIndex(where: \.isPinned).map { $0 + 1 } ?? 0
    }

    private func firstUnpinnedTabInsertionIndex(in tabs: [WorkspaceEditorTabState]) -> Int {
        tabs.firstIndex(where: { !$0.isPinned }) ?? tabs.count
    }
}
