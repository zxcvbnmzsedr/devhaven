import SwiftUI
import DevHavenCore

struct WorkspaceDiffTabView: View {
    @Bindable var viewModel: WorkspaceDiffTabViewModel
    let displayOptions: WorkspaceEditorDisplayOptions

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceDiffNavigationBarView(
                navigatorState: viewModel.viewerDescriptor?.navigatorState ?? viewModel.sessionState.navigatorState,
                viewerMode: Binding(
                    get: { effectiveViewerMode },
                    set: { newMode in
                        guard availableViewerModes.contains(newMode) else {
                            return
                        }
                        viewModel.updateViewerMode(newMode)
                    }
                ),
                availableViewerModes: availableViewerModes,
                onRefresh: { viewModel.refresh() },
                onPreviousDifference: { viewModel.goToPreviousDifference() },
                onNextDifference: { viewModel.goToNextDifference() }
            ) {
                if effectiveViewerMode == .sideBySide, viewModel.editableContentText != nil {
                    Button("保存") {
                        try? viewModel.saveEditableContent()
                    }
                    .buttonStyle(.borderless)
                }

                if effectiveViewerMode == .sideBySide, viewModel.documentState.loadedMergeDocument != nil {
                    Button("接受 Ours") {
                        viewModel.applyMergeAction(.acceptOurs)
                    }
                    .buttonStyle(.borderless)

                    Button("接受 Theirs") {
                        viewModel.applyMergeAction(.acceptTheirs)
                    }
                    .buttonStyle(.borderless)

                    Button("接受 Both") {
                        viewModel.applyMergeAction(.acceptBoth)
                    }
                    .buttonStyle(.borderless)
                }
            }

            Divider()
                .overlay(NativeTheme.border)

            contentStateView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(NativeTheme.window)
        .onAppear {
            if case .idle = viewModel.documentState.loadState {
                viewModel.refresh()
            }
        }
    }

    private var effectiveViewerMode: WorkspaceDiffViewerMode {
        switch viewModel.documentState.loadState {
        case .loaded(.merge):
            return .sideBySide
        default:
            return viewModel.documentState.viewerMode
        }
    }

    private var availableViewerModes: [WorkspaceDiffViewerMode] {
        switch viewModel.documentState.loadState {
        case .loaded(.merge):
            return [.sideBySide]
        default:
            return [.sideBySide, .unified]
        }
    }

    @ViewBuilder
    private var contentStateView: some View {
        switch viewModel.documentState.loadState {
        case .idle, .loading:
            ProgressView("正在加载 Diff…")
                .tint(NativeTheme.accent)
        case let .failed(message):
            ContentUnavailableView(
                "Diff 加载失败",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
            .foregroundStyle(NativeTheme.textSecondary)
        case let .loaded(document):
            switch document {
            case let .patch(patchDocument):
                WorkspaceDiffPatchViewerView(
                    document: patchDocument,
                    viewerMode: effectiveViewerMode,
                    paneDescriptors: viewModel.viewerDescriptor?.paneDescriptors ?? []
                )
            case let .compare(compareDocument):
                if effectiveViewerMode == .unified {
                    WorkspaceDiffPatchViewerView(
                        document: unifiedPatchDocument(for: compareDocument),
                        viewerMode: .unified,
                        paneDescriptors: viewModel.viewerDescriptor?.paneDescriptors ?? []
                    )
                } else {
                    WorkspaceDiffTwoSideViewerView(
                        viewModel: viewModel,
                        document: compareDocument,
                        paneDescriptors: viewModel.viewerDescriptor?.paneDescriptors ?? [],
                        selectedDifference: viewModel.viewerDescriptor?.selectedDifference,
                        displayOptions: displayOptions
                    )
                }
            case let .merge(mergeDocument):
                WorkspaceDiffMergeViewerView(
                    viewModel: viewModel,
                    document: mergeDocument,
                    paneDescriptors: viewModel.viewerDescriptor?.paneDescriptors ?? [],
                    selectedDifference: viewModel.viewerDescriptor?.selectedDifference,
                    displayOptions: displayOptions
                )
            }
        }
    }
}

private func unifiedPatchDocument(for document: WorkspaceDiffCompareDocument) -> WorkspaceDiffParsedDocument {
    let oldPath = document.leftPane.path ?? document.rightPane.path
    let newPath = document.rightPane.path ?? document.leftPane.path
    guard !document.blocks.isEmpty else {
        return WorkspaceDiffParsedDocument(
            kind: .empty,
            oldPath: oldPath,
            newPath: newPath,
            headerLines: [],
            hunks: [],
            message: "暂无可展示内容"
        )
    }

    let oldLines = normalizedDiffDisplayLines(document.leftPane.text)
    let newLines = normalizedDiffDisplayLines(document.rightPane.text)
    var hunks = [WorkspaceDiffHunk]()
    var currentOldIndex = 0
    var currentNewIndex = 0

    for block in document.blocks {
        var hunkLines = [WorkspaceDiffLine]()
        let blockOldStart = min(block.leftLineRange.startLine, oldLines.count)
        let blockNewStart = min(block.rightLineRange.startLine, newLines.count)

        while currentOldIndex < blockOldStart, currentNewIndex < blockNewStart {
            hunkLines.append(
                WorkspaceDiffLine(
                    kind: .context,
                    oldLineNumber: currentOldIndex + 1,
                    newLineNumber: currentNewIndex + 1,
                    text: newLines[currentNewIndex]
                )
            )
            currentOldIndex += 1
            currentNewIndex += 1
        }

        for (offset, line) in block.leftLines.enumerated() {
            hunkLines.append(
                WorkspaceDiffLine(
                    kind: .removed,
                    oldLineNumber: block.leftLineRange.startLine + offset + 1,
                    newLineNumber: nil,
                    text: line
                )
            )
        }

        for (offset, line) in block.rightLines.enumerated() {
            hunkLines.append(
                WorkspaceDiffLine(
                    kind: .added,
                    oldLineNumber: nil,
                    newLineNumber: block.rightLineRange.startLine + offset + 1,
                    text: line
                )
            )
        }

        currentOldIndex = block.leftLineRange.startLine + block.leftLineRange.lineCount
        currentNewIndex = block.rightLineRange.startLine + block.rightLineRange.lineCount

        hunks.append(
            WorkspaceDiffHunk(
                header: block.summary,
                lines: hunkLines,
                sideBySideRows: []
            )
        )
    }

    if currentOldIndex < oldLines.count, currentNewIndex < newLines.count {
        var trailingLines = [WorkspaceDiffLine]()
        while currentOldIndex < oldLines.count, currentNewIndex < newLines.count {
            trailingLines.append(
                WorkspaceDiffLine(
                    kind: .context,
                    oldLineNumber: currentOldIndex + 1,
                    newLineNumber: currentNewIndex + 1,
                    text: newLines[currentNewIndex]
                )
            )
            currentOldIndex += 1
            currentNewIndex += 1
        }
        if !trailingLines.isEmpty {
            hunks.append(
                WorkspaceDiffHunk(
                    header: "尾部上下文",
                    lines: trailingLines,
                    sideBySideRows: []
                )
            )
        }
    }

    return WorkspaceDiffParsedDocument(
        kind: .text,
        oldPath: oldPath,
        newPath: newPath,
        headerLines: [],
        hunks: hunks
    )
}

private func normalizedDiffDisplayLines(_ text: String) -> [String] {
    var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    if text.hasSuffix("\n"), lines.last == "" {
        lines.removeLast()
    }
    return lines
}
