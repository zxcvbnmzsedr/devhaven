import SwiftUI
import DevHavenCore

struct WorkspaceDiffTwoSideViewerView: View {
    @Bindable var viewModel: WorkspaceDiffTabViewModel
    let document: WorkspaceDiffCompareDocument
    let paneDescriptors: [WorkspaceDiffPaneDescriptor]
    let selectedDifference: WorkspaceDiffDifferenceAnchor?

    @State private var selectedCompareBlockID: String?
    @State private var scrollSyncState = WorkspaceTextEditorScrollSyncState()
    @State private var scrollRequestState = WorkspaceTextEditorScrollRequestState()

    var body: some View {
        HStack(spacing: 0) {
            compareOverviewGutter

            HSplitView {
                editorPane(
                    document.leftPane,
                    role: .left,
                    editorID: "compare-left",
                    text: .constant(document.leftPane.text)
                )
                .frame(minWidth: 280)

                editorPane(
                    document.rightPane,
                    role: .right,
                    editorID: "compare-right",
                    text: compareEditorBinding
                )
                .frame(minWidth: 280)
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

    private var compareOverviewGutter: some View {
        let totalLineCount = max(compareDocumentLineCount(document), 1)
        return VStack(spacing: 0) {
            Color.clear
                .frame(height: 48)

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
                            scrollCompareBlockIntoView(block, kind: .manual)
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
                scrollRequestState: $scrollRequestState,
                decorationRefreshPolicy: pane.isEditable
                    ? .debounced(nanoseconds: 180_000_000)
                    : .immediate
            )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 0)
                .stroke(NativeTheme.border.opacity(0.65), lineWidth: 1)
        }
    }

    private var compareEditorBinding: Binding<String> {
        Binding(
            get: {
                viewModel.documentState.loadedCompareDocument?.rightPane.text ?? document.rightPane.text
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
        guard case let .compareBlock(blockID)? = selectedDifference,
              let block = document.blocks.first(where: { $0.id == blockID })
        else {
            return
        }
        selectedCompareBlockID = block.id
        scrollCompareBlockIntoView(block, kind: .selectedDifference)
    }

    private func scrollCompareBlockIntoView(
        _ block: WorkspaceDiffCompareBlock,
        kind: WorkspaceTextEditorScrollRequestKind
    ) {
        scrollRequestState = WorkspaceTextEditorScrollRequestState(
            lineTargets: [
                "compare-left": block.leftLineRange.startLine,
                "compare-right": block.rightLineRange.startLine,
            ],
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
