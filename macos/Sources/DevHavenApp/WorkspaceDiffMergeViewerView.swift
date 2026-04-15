import SwiftUI
import DevHavenCore

struct WorkspaceDiffMergeViewerView: View {
    @Bindable var viewModel: WorkspaceDiffTabViewModel
    let document: WorkspaceDiffMergeDocument
    let paneDescriptors: [WorkspaceDiffPaneDescriptor]
    let selectedDifference: WorkspaceDiffDifferenceAnchor?
    let displayOptions: WorkspaceEditorDisplayOptions

    @State private var selectedMergeBlockID: String?
    @StateObject private var oursPaneBridge = WorkspaceMonacoEditorBridge()
    @StateObject private var basePaneBridge = WorkspaceMonacoEditorBridge()
    @StateObject private var theirsPaneBridge = WorkspaceMonacoEditorBridge()
    @StateObject private var resultPaneBridge = WorkspaceMonacoEditorBridge()

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

            WorkspaceMonacoEditorView(
                filePath: pane.path ?? pane.title,
                text: text,
                isEditable: pane.isEditable,
                shouldRequestFocus: false,
                displayOptions: displayOptions,
                highlights: pane.highlights,
                inlineHighlights: pane.inlineHighlights,
                bridge: bridge(for: role),
                onSaveRequested: {
                    if pane.isEditable {
                        try? viewModel.saveEditableContent()
                    }
                }
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

    private func bridge(for role: WorkspaceDiffPaneHeaderRole) -> WorkspaceMonacoEditorBridge {
        switch role {
        case .ours:
            return oursPaneBridge
        case .base:
            return basePaneBridge
        case .theirs:
            return theirsPaneBridge
        case .result:
            return resultPaneBridge
        default:
            return resultPaneBridge
        }
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
        if let oursLineRange = block.oursLineRange {
            oursPaneBridge.revealLine(oursLineRange.startLine + 1)
        }
        if let theirsLineRange = block.theirsLineRange {
            theirsPaneBridge.revealLine(theirsLineRange.startLine + 1)
        }
        if let baseLine = [block.oursLineRange?.startLine, block.theirsLineRange?.startLine]
            .compactMap({ $0 })
            .min()
        {
            basePaneBridge.revealLine(baseLine + 1)
        }

        if kind == .selectedDifference {
            resultPaneBridge.revealLine(block.resultLineRange.startLine + 1)
        } else {
            resultPaneBridge.goToLine(block.resultLineRange.startLine + 1)
        }
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
