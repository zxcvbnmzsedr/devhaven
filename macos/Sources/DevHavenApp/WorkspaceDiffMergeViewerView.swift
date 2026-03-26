import SwiftUI
import DevHavenCore

struct WorkspaceDiffMergeViewerView: View {
    @Bindable var viewModel: WorkspaceDiffTabViewModel
    let document: WorkspaceDiffMergeDocument
    let paneDescriptors: [WorkspaceDiffPaneDescriptor]
    let selectedDifference: WorkspaceDiffDifferenceAnchor?
    @Binding var scrollSyncState: WorkspaceTextEditorScrollSyncState
    @Binding var scrollRequestState: WorkspaceTextEditorScrollRequestState

    @State private var selectedMergeBlockID: String?

    var body: some View {
        HStack(spacing: 0) {
            mergeConflictSidebar
            mergeOverviewGutter

            VSplitView {
                HSplitView {
                    editorPane(document.oursPane, role: .ours, editorID: "merge-ours", text: .constant(document.oursPane.text))
                        .frame(minWidth: 220)
                    editorPane(document.basePane, role: .base, editorID: "merge-base", text: .constant(document.basePane.text))
                        .frame(minWidth: 220)
                    editorPane(document.theirsPane, role: .theirs, editorID: "merge-theirs", text: .constant(document.theirsPane.text))
                        .frame(minWidth: 220)
                }
                .frame(minHeight: 220)

                editorPane(document.resultPane, role: .result, editorID: "merge-result", text: mergeResultBinding)
                    .frame(minHeight: 180)
            }
        }
        .background(NativeTheme.window)
        .onAppear {
            syncSelection(with: selectedDifference)
        }
        .onChange(of: selectedDifference) { _, newValue in
            syncSelection(with: newValue)
        }
    }

    private var mergeConflictSidebar: some View {
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
                                    scrollMergeBlockIntoView(block, kind: .manual)
                                    viewModel.applyMergeAction(.acceptOurs, blockID: block.id)
                                }
                                .buttonStyle(.borderless)

                                Button("Theirs") {
                                    selectedMergeBlockID = block.id
                                    scrollMergeBlockIntoView(block, kind: .manual)
                                    viewModel.applyMergeAction(.acceptTheirs, blockID: block.id)
                                }
                                .buttonStyle(.borderless)

                                Button("Both") {
                                    selectedMergeBlockID = block.id
                                    scrollMergeBlockIntoView(block, kind: .manual)
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
                            scrollMergeBlockIntoView(block, kind: .manual)
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

    private var mergeOverviewGutter: some View {
        let totalLineCount = max(mergeDocumentLineCount(document), 1)
        return VStack(spacing: 0) {
            Color.clear
                .frame(height: 48)

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
                            scrollMergeBlockIntoView(block, kind: .manual)
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

    private func editorPane(
        _ pane: WorkspaceDiffEditorPane,
        role: WorkspaceDiffPaneHeaderRole,
        editorID: String,
        text: Binding<String>
    ) -> some View {
        VStack(spacing: 0) {
            WorkspaceDiffPaneHeaderView(descriptor: paneDescriptor(for: role, fallbackTitle: pane.title, fallbackPath: pane.path))

            WorkspaceTextEditorView(
                editorID: editorID,
                text: text,
                isEditable: pane.isEditable,
                highlights: pane.highlights,
                inlineHighlights: pane.inlineHighlights,
                scrollSyncState: $scrollSyncState,
                scrollRequestState: $scrollRequestState
            )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 0)
                .stroke(NativeTheme.border.opacity(0.65), lineWidth: 1)
        }
    }

    private var mergeResultBinding: Binding<String> {
        Binding(
            get: {
                viewModel.documentState.loadedMergeDocument?.resultPane.text ?? document.resultPane.text
            },
            set: { viewModel.updateEditableContent($0) }
        )
    }

    private func paneDescriptor(
        for role: WorkspaceDiffPaneHeaderRole,
        fallbackTitle: String,
        fallbackPath: String?
    ) -> WorkspaceDiffPaneDescriptor {
        if let descriptor = paneDescriptors.first(where: { $0.role == role }) {
            return descriptor
        }
        return WorkspaceDiffPaneDescriptor(
            role: role,
            metadata: WorkspaceDiffPaneMetadata(title: fallbackTitle, path: fallbackPath)
        )
    }

    private func syncSelection(with selectedDifference: WorkspaceDiffDifferenceAnchor?) {
        guard case let .mergeConflict(blockID)? = selectedDifference,
              let block = document.conflictBlocks.first(where: { $0.id == blockID })
        else {
            return
        }
        selectedMergeBlockID = block.id
        scrollMergeBlockIntoView(block, kind: .selectedDifference)
    }

    private func scrollMergeBlockIntoView(
        _ block: WorkspaceDiffMergeConflictBlock,
        kind: WorkspaceTextEditorScrollRequestKind
    ) {
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

        scrollRequestState = WorkspaceTextEditorScrollRequestState(
            lineTargets: lineTargets,
            revision: scrollRequestState.revision + 1,
            kind: kind == .selectedDifference
                ? WorkspaceTextEditorScrollRequestKind.selectedDifference
                : WorkspaceTextEditorScrollRequestKind.manual
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
}
