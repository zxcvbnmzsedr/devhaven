import SwiftUI
import DevHavenCore

struct WorkspaceDiffTabView: View {
    @Bindable var viewModel: WorkspaceDiffTabViewModel
    @State private var editorScrollSyncState = WorkspaceTextEditorScrollSyncState()
    @State private var editorScrollRequestState = WorkspaceTextEditorScrollRequestState()
    @State private var selectedCompareBlockID: String?
    @State private var selectedMergeBlockID: String?

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceDiffNavigationBarView(
                navigatorState: viewModel.viewerDescriptor?.navigatorState ?? viewModel.sessionState.navigatorState,
                viewerMode: Binding(
                    get: { viewModel.documentState.viewerMode },
                    set: { viewModel.updateViewerMode($0) }
                ),
                onRefresh: { viewModel.refresh() },
                onPreviousDifference: { viewModel.goToPreviousDifference() },
                onNextDifference: { viewModel.goToNextDifference() }
            ) {
                if viewModel.editableContentText != nil {
                    Button("保存") {
                        try? viewModel.saveEditableContent()
                    }
                    .buttonStyle(.borderless)
                }

                if viewModel.documentState.loadedMergeDocument != nil {
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
                patchViewerContent(patchDocument)
            case let .compare(compareDocument):
                compareEditorContent(compareDocument)
            case let .merge(mergeDocument):
                mergeEditorContent(mergeDocument)
            }
        }
    }

    @ViewBuilder
    private func patchViewerContent(_ document: WorkspaceDiffParsedDocument) -> some View {
        switch document.kind {
        case .text:
            if viewModel.documentState.viewerMode == .sideBySide {
                sideBySideDiffContent(document)
            } else {
                unifiedDiffContent(document)
            }
        case .empty, .binary, .unsupported:
            ContentUnavailableView(
                documentTitle(for: document.kind),
                systemImage: systemImage(for: document.kind),
                description: Text(document.message ?? "暂无可展示内容")
            )
            .foregroundStyle(NativeTheme.textSecondary)
        }
    }

    private func compareEditorContent(_ document: WorkspaceDiffCompareDocument) -> some View {
        HStack(spacing: 0) {
            compareBlocksSidebar(document)
            compareOverviewGutter(document)

            HSplitView {
                editorPane(
                    document.leftPane,
                    role: .left,
                    editorID: "compare-left",
                    text: .constant(document.leftPane.text),
                    scrollSyncState: $editorScrollSyncState,
                    scrollRequestState: $editorScrollRequestState
                )
                .frame(minWidth: 280)

                editorPane(
                    document.rightPane,
                    role: .right,
                    editorID: "compare-right",
                    text: compareEditorBinding(document),
                    scrollSyncState: $editorScrollSyncState,
                    scrollRequestState: $editorScrollRequestState
                )
                .frame(minWidth: 280)
            }
        }
        .background(NativeTheme.window)
    }

    private func mergeEditorContent(_ document: WorkspaceDiffMergeDocument) -> some View {
        HStack(spacing: 0) {
            mergeConflictSidebar(document)
            mergeOverviewGutter(document)

            VSplitView {
                HSplitView {
                    editorPane(
                        document.oursPane,
                        role: .ours,
                        editorID: "merge-ours",
                        text: .constant(document.oursPane.text),
                        scrollSyncState: $editorScrollSyncState,
                        scrollRequestState: $editorScrollRequestState
                    )
                    .frame(minWidth: 220)

                    editorPane(
                        document.basePane,
                        role: .base,
                        editorID: "merge-base",
                        text: .constant(document.basePane.text),
                        scrollSyncState: $editorScrollSyncState,
                        scrollRequestState: $editorScrollRequestState
                    )
                    .frame(minWidth: 220)

                    editorPane(
                        document.theirsPane,
                        role: .theirs,
                        editorID: "merge-theirs",
                        text: .constant(document.theirsPane.text),
                        scrollSyncState: $editorScrollSyncState,
                        scrollRequestState: $editorScrollRequestState
                    )
                    .frame(minWidth: 220)
                }
                .frame(minHeight: 220)

                editorPane(
                    document.resultPane,
                    role: .result,
                    editorID: "merge-result",
                    text: mergeResultBinding(document),
                    scrollSyncState: $editorScrollSyncState,
                    scrollRequestState: $editorScrollRequestState
                )
                .frame(minHeight: 180)
            }
        }
        .background(NativeTheme.window)
    }

    private func compareOverviewGutter(_ document: WorkspaceDiffCompareDocument) -> some View {
        let totalLineCount = max(compareDocumentLineCount(document), 1)
        return VStack(spacing: 0) {
            Color.clear
                .frame(height: 34)

            GeometryReader { proxy in
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(NativeTheme.surface)

                    ForEach(document.blocks) { block in
                        let markerFrame = overviewMarkerFrame(
                            startLine: compareMarkerStartLine(for: block),
                            lineCount: compareMarkerLineCount(for: block),
                            totalLineCount: totalLineCount,
                            availableHeight: proxy.size.height
                        )
                        blockOverviewMarker(
                            color: compareOverviewMarkerColor(for: block, mode: document.mode),
                            isSelected: selectedCompareBlockID == block.id,
                            accessibilityLabel: block.summary
                        ) {
                            selectedCompareBlockID = block.id
                            scrollCompareBlockIntoView(block)
                        }
                        .frame(width: 8, height: markerFrame.height)
                        .offset(y: markerFrame.minY)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .frame(width: 18)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(NativeTheme.border.opacity(0.7))
                .frame(width: 1)
        }
    }

    private func mergeOverviewGutter(_ document: WorkspaceDiffMergeDocument) -> some View {
        let totalLineCount = max(mergeDocumentLineCount(document), 1)
        return VStack(spacing: 0) {
            Color.clear
                .frame(height: 34)

            GeometryReader { proxy in
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(NativeTheme.surface)

                    ForEach(document.conflictBlocks) { block in
                        let markerFrame = overviewMarkerFrame(
                            startLine: block.resultLineRange.startLine,
                            lineCount: max(block.resultLineRange.lineCount, 1),
                            totalLineCount: totalLineCount,
                            availableHeight: proxy.size.height
                        )
                        blockOverviewMarker(
                            color: .orange.opacity(0.82),
                            isSelected: selectedMergeBlockID == block.id,
                            accessibilityLabel: block.summary
                        ) {
                            selectedMergeBlockID = block.id
                            scrollMergeBlockIntoView(block)
                        }
                        .frame(width: 8, height: markerFrame.height)
                        .offset(y: markerFrame.minY)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .frame(width: 18)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(NativeTheme.border.opacity(0.7))
                .frame(width: 1)
        }
    }

    private func compareBlocksSidebar(_ document: WorkspaceDiffCompareDocument) -> some View {
        VStack(spacing: 0) {
            Text("Diff Blocks")
                .font(.caption.weight(.semibold))
                .foregroundStyle(NativeTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(NativeTheme.surface)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(document.blocks) { block in
                        let isSelected = selectedCompareBlockID == block.id
                        VStack(alignment: .leading, spacing: 8) {
                            Text(block.summary)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(NativeTheme.textPrimary)
                            HStack(spacing: 8) {
                                if document.mode == .unstaged || document.mode == .untracked {
                                    Button("暂存") {
                                        selectedCompareBlockID = block.id
                                        scrollCompareBlockIntoView(block)
                                        try? viewModel.applyCompareBlockAction(.stage, blockID: block.id)
                                    }
                                    .buttonStyle(.borderless)

                                    if document.mode == .unstaged, document.rightPane.isEditable {
                                        Button("回退") {
                                            selectedCompareBlockID = block.id
                                            scrollCompareBlockIntoView(block)
                                            try? viewModel.applyCompareBlockAction(.revert, blockID: block.id)
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                } else if document.mode == .staged {
                                    Button("撤销暂存") {
                                        selectedCompareBlockID = block.id
                                        scrollCompareBlockIntoView(block)
                                        try? viewModel.applyCompareBlockAction(.unstage, blockID: block.id)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(isSelected ? NativeTheme.accent.opacity(0.12) : NativeTheme.surface)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    isSelected ? NativeTheme.accent.opacity(0.9) : NativeTheme.border.opacity(0.65),
                                    lineWidth: 1
                                )
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedCompareBlockID = block.id
                            scrollCompareBlockIntoView(block)
                        }
                    }
                }
                .padding(10)
            }
        }
        .frame(width: 220)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(NativeTheme.border.opacity(0.8))
                .frame(width: 1)
        }
    }

    private func mergeConflictSidebar(_ document: WorkspaceDiffMergeDocument) -> some View {
        VStack(spacing: 0) {
            Text("Conflict Blocks")
                .font(.caption.weight(.semibold))
                .foregroundStyle(NativeTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(NativeTheme.surface)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(document.conflictBlocks) { block in
                        let isSelected = selectedMergeBlockID == block.id
                        VStack(alignment: .leading, spacing: 8) {
                            Text(block.summary)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(NativeTheme.textPrimary)
                            HStack(spacing: 8) {
                                Button("Ours") {
                                    selectedMergeBlockID = block.id
                                    scrollMergeBlockIntoView(block)
                                    viewModel.applyMergeAction(.acceptOurs, blockID: block.id)
                                }
                                .buttonStyle(.borderless)

                                Button("Theirs") {
                                    selectedMergeBlockID = block.id
                                    scrollMergeBlockIntoView(block)
                                    viewModel.applyMergeAction(.acceptTheirs, blockID: block.id)
                                }
                                .buttonStyle(.borderless)

                                Button("Both") {
                                    selectedMergeBlockID = block.id
                                    scrollMergeBlockIntoView(block)
                                    viewModel.applyMergeAction(.acceptBoth, blockID: block.id)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(isSelected ? NativeTheme.accent.opacity(0.12) : NativeTheme.surface)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    isSelected ? NativeTheme.accent.opacity(0.9) : NativeTheme.border.opacity(0.65),
                                    lineWidth: 1
                                )
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedMergeBlockID = block.id
                            scrollMergeBlockIntoView(block)
                        }
                    }
                }
                .padding(10)
            }
        }
        .frame(width: 220)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(NativeTheme.border.opacity(0.8))
                .frame(width: 1)
        }
    }

    private func compareBlocksStrip(_ document: WorkspaceDiffCompareDocument) -> some View {
        guard !document.blocks.isEmpty else {
            return AnyView(EmptyView())
        }
        return AnyView(
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(document.blocks) { block in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(block.summary)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(NativeTheme.textPrimary)
                            HStack(spacing: 8) {
                                if document.mode == .unstaged || document.mode == .untracked {
                                    Button("暂存此块") {
                                        try? viewModel.applyCompareBlockAction(.stage, blockID: block.id)
                                    }
                                    .buttonStyle(.borderless)

                                    if document.mode == .unstaged, document.rightPane.isEditable {
                                        Button("回退此块") {
                                            try? viewModel.applyCompareBlockAction(.revert, blockID: block.id)
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                } else if document.mode == .staged {
                                    Button("撤销暂存此块") {
                                        try? viewModel.applyCompareBlockAction(.unstage, blockID: block.id)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(NativeTheme.surface)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(NativeTheme.border.opacity(0.65), lineWidth: 1)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background(NativeTheme.window)
        )
    }

    private func mergeConflictBlocksStrip(_ document: WorkspaceDiffMergeDocument) -> some View {
        guard !document.conflictBlocks.isEmpty else {
            return AnyView(EmptyView())
        }
        return AnyView(
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(document.conflictBlocks) { block in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(block.summary)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(NativeTheme.textPrimary)
                            HStack(spacing: 8) {
                                Button("接受 Ours") {
                                    viewModel.applyMergeAction(.acceptOurs, blockID: block.id)
                                }
                                .buttonStyle(.borderless)

                                Button("接受 Theirs") {
                                    viewModel.applyMergeAction(.acceptTheirs, blockID: block.id)
                                }
                                .buttonStyle(.borderless)

                                Button("接受 Both") {
                                    viewModel.applyMergeAction(.acceptBoth, blockID: block.id)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(NativeTheme.surface)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(NativeTheme.border.opacity(0.65), lineWidth: 1)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background(NativeTheme.window)
        )
    }

    private func editorPane(
        _ pane: WorkspaceDiffEditorPane,
        role: WorkspaceDiffPaneHeaderRole,
        editorID: String,
        text: Binding<String>,
        scrollSyncState: Binding<WorkspaceTextEditorScrollSyncState>,
        scrollRequestState: Binding<WorkspaceTextEditorScrollRequestState>
    ) -> some View {
        VStack(spacing: 0) {
            WorkspaceDiffPaneHeaderView(
                descriptor: paneDescriptor(
                    for: role,
                    fallbackTitle: pane.title,
                    fallbackPath: pane.path
                )
            )

            WorkspaceTextEditorView(
                editorID: editorID,
                text: text,
                isEditable: pane.isEditable,
                highlights: pane.highlights,
                inlineHighlights: pane.inlineHighlights,
                scrollSyncState: scrollSyncState,
                scrollRequestState: scrollRequestState
            )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 0)
                .stroke(NativeTheme.border.opacity(0.65), lineWidth: 1)
        }
    }

    private func paneDescriptor(
        for role: WorkspaceDiffPaneHeaderRole,
        fallbackTitle: String,
        fallbackPath: String?
    ) -> WorkspaceDiffPaneDescriptor {
        if let descriptor = viewModel.viewerDescriptor?.paneDescriptors.first(where: { $0.role == role }) {
            return descriptor
        }
        return WorkspaceDiffPaneDescriptor(
            role: role,
            metadata: WorkspaceDiffPaneMetadata(
                title: fallbackTitle,
                path: fallbackPath
            )
        )
    }

    private func scrollCompareBlockIntoView(_ block: WorkspaceDiffCompareBlock) {
        editorScrollRequestState = WorkspaceTextEditorScrollRequestState(
            lineTargets: [
                "compare-left": block.leftLineRange.startLine,
                "compare-right": block.rightLineRange.startLine,
            ],
            revision: editorScrollRequestState.revision + 1
        )
    }

    private func scrollMergeBlockIntoView(_ block: WorkspaceDiffMergeConflictBlock) {
        var lineTargets: [String: Int] = [
            "merge-result": block.resultLineRange.startLine
        ]
        if let oursLineRange = block.oursLineRange {
            lineTargets["merge-ours"] = oursLineRange.startLine
        }
        if let theirsLineRange = block.theirsLineRange {
            lineTargets["merge-theirs"] = theirsLineRange.startLine
        }
        if let baseLine = [block.oursLineRange?.startLine, block.theirsLineRange?.startLine]
            .compactMap({ $0 })
            .min()
        {
            lineTargets["merge-base"] = baseLine
        }
        editorScrollRequestState = WorkspaceTextEditorScrollRequestState(
            lineTargets: lineTargets,
            revision: editorScrollRequestState.revision + 1
        )
    }

    private func blockOverviewMarker(
        color: Color,
        isSelected: Bool,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? NativeTheme.accent : color)
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isSelected ? NativeTheme.accent.opacity(0.95) : color.opacity(0.9), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .help(accessibilityLabel)
    }

    private func compareOverviewMarkerColor(
        for block: WorkspaceDiffCompareBlock,
        mode: WorkspaceDiffCompareMode
    ) -> Color {
        if block.leftLineRange.lineCount == 0 {
            return .green.opacity(0.82)
        }
        if block.rightLineRange.lineCount == 0 {
            return .red.opacity(0.82)
        }
        switch mode {
        case .staged, .unstaged, .untracked:
            return .yellow.opacity(0.82)
        }
    }

    private func compareMarkerStartLine(for block: WorkspaceDiffCompareBlock) -> Int {
        let candidates = [
            block.leftLineRange.lineCount > 0 ? block.leftLineRange.startLine : nil,
            block.rightLineRange.lineCount > 0 ? block.rightLineRange.startLine : nil,
        ]
        return candidates.compactMap { $0 }.min() ?? 0
    }

    private func compareMarkerLineCount(for block: WorkspaceDiffCompareBlock) -> Int {
        max(max(block.leftLineRange.lineCount, block.rightLineRange.lineCount), 1)
    }

    private func compareDocumentLineCount(_ document: WorkspaceDiffCompareDocument) -> Int {
        let maxDocumentLines = max(
            editorDisplayLineCount(document.leftPane.text),
            editorDisplayLineCount(document.rightPane.text)
        )
        let maxBlockEndLine = document.blocks
            .map { max($0.leftLineRange.endLine, $0.rightLineRange.endLine) }
            .max() ?? 0
        return max(maxDocumentLines, maxBlockEndLine)
    }

    private func mergeDocumentLineCount(_ document: WorkspaceDiffMergeDocument) -> Int {
        max(
            editorDisplayLineCount(document.resultPane.text),
            document.conflictBlocks.map { $0.resultLineRange.endLine }.max() ?? 0
        )
    }

    private func overviewMarkerFrame(
        startLine: Int,
        lineCount: Int,
        totalLineCount: Int,
        availableHeight: CGFloat
    ) -> CGRect {
        let safeHeight = max(availableHeight - 12, 1)
        let denominator = max(totalLineCount, 1)
        let startRatio = CGFloat(max(0, startLine)) / CGFloat(denominator)
        let heightRatio = CGFloat(max(1, lineCount)) / CGFloat(denominator)
        let markerHeight = max(10, safeHeight * heightRatio)
        let maxOffset = max(0, safeHeight - markerHeight)
        let offsetY = min(maxOffset, safeHeight * startRatio)
        return CGRect(x: 0, y: offsetY, width: 8, height: markerHeight)
    }

    private func compareEditorBinding(_ document: WorkspaceDiffCompareDocument) -> Binding<String> {
        Binding(
            get: {
                viewModel.documentState.loadedCompareDocument?.rightPane.text ?? document.rightPane.text
            },
            set: { viewModel.updateEditableContent($0) }
        )
    }

    private func mergeResultBinding(_ document: WorkspaceDiffMergeDocument) -> Binding<String> {
        Binding(
            get: {
                viewModel.documentState.loadedMergeDocument?.resultPane.text ?? document.resultPane.text
            },
            set: { viewModel.updateEditableContent($0) }
        )
    }

    private func sideBySideDiffContent(_ document: WorkspaceDiffParsedDocument) -> some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(document.hunks.indices, id: \.self) { hunkIndex in
                    let hunk = document.hunks[hunkIndex]
                    hunkHeader(hunk.header)
                    ForEach(hunk.sideBySideRows.indices, id: \.self) { rowIndex in
                        let row = hunk.sideBySideRows[rowIndex]
                        HStack(spacing: 0) {
                            sideBySideColumn(line: row.leftLine, alignment: .leading)
                            sideBySideColumn(line: row.rightLine, alignment: .leading)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(NativeTheme.window)
    }

    private func unifiedDiffContent(_ document: WorkspaceDiffParsedDocument) -> some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(document.hunks.indices, id: \.self) { hunkIndex in
                    let hunk = document.hunks[hunkIndex]
                    hunkHeader(hunk.header)
                    ForEach(hunk.lines.indices, id: \.self) { lineIndex in
                        unifiedRow(hunk.lines[lineIndex])
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(NativeTheme.window)
    }

    private func hunkHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.monospaced())
            .foregroundStyle(NativeTheme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NativeTheme.surface)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(NativeTheme.border.opacity(0.8))
                    .frame(height: 1)
            }
    }

    private func sideBySideColumn(line: WorkspaceDiffLine?, alignment: Alignment) -> some View {
        HStack(spacing: 0) {
            Text(line.map(oldLineNumberText(for:)) ?? "")
                .font(.caption.monospacedDigit())
                .foregroundStyle(NativeTheme.textSecondary)
                .frame(width: 48, alignment: .trailing)
                .padding(.trailing, 8)

            Text(line.map(newLineNumberText(for:)) ?? "")
                .font(.caption.monospacedDigit())
                .foregroundStyle(NativeTheme.textSecondary)
                .frame(width: 48, alignment: .trailing)
                .padding(.trailing, 8)

            Text(line?.text ?? "")
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(NativeTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: alignment)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: alignment)
        .background(backgroundColor(for: line))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(NativeTheme.border.opacity(0.35))
                .frame(height: 1)
        }
    }

    private func unifiedRow(_ line: WorkspaceDiffLine) -> some View {
        HStack(spacing: 0) {
            Text(oldLineNumberText(for: line))
                .font(.caption.monospacedDigit())
                .foregroundStyle(NativeTheme.textSecondary)
                .frame(width: 48, alignment: .trailing)
                .padding(.trailing, 8)

            Text(newLineNumberText(for: line))
                .font(.caption.monospacedDigit())
                .foregroundStyle(NativeTheme.textSecondary)
                .frame(width: 48, alignment: .trailing)
                .padding(.trailing, 8)

            Text(line.text)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(NativeTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(backgroundColor(for: line))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(NativeTheme.border.opacity(0.35))
                .frame(height: 1)
        }
    }

    private func oldLineNumberText(for line: WorkspaceDiffLine) -> String {
        line.oldLineNumber.map(String.init) ?? ""
    }

    private func newLineNumberText(for line: WorkspaceDiffLine) -> String {
        line.newLineNumber.map(String.init) ?? ""
    }

    private func backgroundColor(for line: WorkspaceDiffLine?) -> Color {
        guard let line else {
            return NativeTheme.window
        }
        switch line.kind {
        case .context:
            return NativeTheme.window
        case .removed:
            return Color.red.opacity(0.10)
        case .added:
            return Color.green.opacity(0.10)
        case .meta:
            return NativeTheme.surface
        }
    }

    private func documentTitle(for kind: WorkspaceDiffDocumentKind) -> String {
        switch kind {
        case .empty:
            return "暂无 Diff"
        case .binary:
            return "二进制文件"
        case .unsupported:
            return "无法预览 Diff"
        case .text:
            return "Diff"
        }
    }

    private func systemImage(for kind: WorkspaceDiffDocumentKind) -> String {
        switch kind {
        case .empty:
            return "doc.text.magnifyingglass"
        case .binary:
            return "doc.fill"
        case .unsupported:
            return "exclamationmark.triangle"
        case .text:
            return "square.split.2x1"
        }
    }
}

private func editorDisplayLineCount(_ text: String) -> Int {
    guard !text.isEmpty else {
        return 1
    }
    var lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
    if text.hasSuffix("\n"), lines > 1 {
        lines -= 1
    }
    return max(lines, 1)
}
