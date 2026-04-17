import Foundation

@MainActor
final class WorkspaceEditorDocumentStore {
    enum ExternalChangeSnapshot {
        case inSync
        case modifiedOnDisk
        case removedOnDisk
    }

    struct MutationResult {
        var tabs: [WorkspaceEditorTabState]
        var didMutate: Bool
    }

    func updateText(
        _ text: String,
        tabID: String,
        in tabs: [WorkspaceEditorTabState]
    ) -> MutationResult {
        mutateTab(tabID, in: tabs) { tab in
            let shouldPromotePreviewTab = tab.isPreview && tab.text != text
            let nextContentFingerprint = tab.kind == .text
                ? workspaceEditorContentFingerprint(text)
                : nil
            tab.text = text
            tab.isDirty = nextContentFingerprint != tab.savedContentFingerprint
            if shouldPromotePreviewTab {
                tab.isPreview = false
            }
        }
    }

    func applyExternalChange(
        _ snapshot: ExternalChangeSnapshot,
        tabID: String,
        in tabs: [WorkspaceEditorTabState]
    ) -> MutationResult {
        mutateTab(tabID, in: tabs) { tab in
            switch snapshot {
            case .removedOnDisk:
                tab.externalChangeState = .removedOnDisk
                if tab.message?.isEmpty != false || isExternalEditorMessage(tab.message) {
                    tab.message = "文件已在磁盘上被删除，请关闭标签页或另存为新文件。"
                }
            case .modifiedOnDisk:
                tab.externalChangeState = .modifiedOnDisk
                if tab.message?.isEmpty != false || isExternalEditorMessage(tab.message) {
                    tab.message = tab.isDirty
                        ? "检测到文件已被外部修改。为避免覆盖磁盘上的新内容，请先重新载入再决定如何处理。"
                        : "检测到文件已被外部修改，可直接重新载入同步磁盘内容。"
                }
            case .inSync:
                tab.externalChangeState = .inSync
                if isExternalEditorMessage(tab.message) {
                    tab.message = nil
                }
            }
        }
    }

    func applyReloadedDocument(
        _ document: WorkspaceEditorDocumentSnapshot,
        tabID: String,
        in tabs: [WorkspaceEditorTabState]
    ) -> MutationResult {
        mutateTab(tabID, in: tabs) { tab in
            tab.kind = document.kind
            tab.text = document.text
            tab.isEditable = document.isEditable
            tab.isDirty = false
            tab.isLoading = false
            tab.isSaving = false
            tab.externalChangeState = .inSync
            tab.message = document.message
            tab.lastLoadedModificationDate = document.modificationDate
            tab.savedContentFingerprint = document.contentFingerprint
        }
    }

    func applySaveBlockedByExternalChange(
        tabID: String,
        in tabs: [WorkspaceEditorTabState]
    ) -> MutationResult {
        mutateTab(tabID, in: tabs) { tab in
            tab.isSaving = false
            tab.message = tab.externalChangeState == .removedOnDisk
                ? "磁盘上的文件已被删除，当前不能直接保存覆盖。请先重新载入或另存为新文件。"
                : "检测到磁盘文件已变化，当前保存已阻止。请先重新载入确认差异。"
        }
    }

    func beginSaving(
        tabID: String,
        in tabs: [WorkspaceEditorTabState]
    ) -> MutationResult {
        mutateTab(tabID, in: tabs) { tab in
            tab.isSaving = true
            tab.message = nil
        }
    }

    func applySavedDocument(
        _ document: WorkspaceEditorDocumentSnapshot,
        tabID: String,
        in tabs: [WorkspaceEditorTabState]
    ) -> MutationResult {
        mutateTab(tabID, in: tabs) { tab in
            tab.kind = document.kind
            tab.text = document.text
            tab.isEditable = document.isEditable
            tab.isDirty = false
            tab.isSaving = false
            tab.externalChangeState = .inSync
            tab.message = document.message
            tab.lastLoadedModificationDate = document.modificationDate
            tab.savedContentFingerprint = document.contentFingerprint
        }
    }

    func applySaveFailure(
        message: String,
        tabID: String,
        in tabs: [WorkspaceEditorTabState]
    ) -> MutationResult {
        mutateTab(tabID, in: tabs) { tab in
            tab.isSaving = false
            tab.message = message
        }
    }

    private func mutateTab(
        _ tabID: String,
        in tabs: [WorkspaceEditorTabState],
        mutate: (inout WorkspaceEditorTabState) -> Void
    ) -> MutationResult {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else {
            return MutationResult(tabs: tabs, didMutate: false)
        }
        var nextTabs = tabs
        mutate(&nextTabs[index])
        return MutationResult(tabs: nextTabs, didMutate: true)
    }

    private func isExternalEditorMessage(_ message: String?) -> Bool {
        guard let message else {
            return false
        }
        return message.hasPrefix("检测到文件已被外部修改")
            || message.hasPrefix("文件已在磁盘上被删除")
            || message.hasPrefix("磁盘上的文件已被删除")
    }
}
