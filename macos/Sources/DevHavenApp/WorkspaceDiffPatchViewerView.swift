import SwiftUI
import DevHavenCore

struct WorkspaceDiffPatchViewerView: View {
    let document: WorkspaceDiffParsedDocument
    let viewerMode: WorkspaceDiffViewerMode
    let paneDescriptors: [WorkspaceDiffPaneDescriptor]

    var body: some View {
        switch document.kind {
        case .text:
            VStack(spacing: 0) {
                if viewerMode == .sideBySide, paneDescriptors.count >= 2 {
                    HStack(spacing: 0) {
                        WorkspaceDiffPaneHeaderView(descriptor: paneDescriptors[0])
                        WorkspaceDiffPaneHeaderView(descriptor: paneDescriptors[1])
                    }
                }

                if viewerMode == .sideBySide {
                    sideBySideDiffContent
                } else {
                    unifiedDiffContent
                }
            }
            .background(NativeTheme.window)
        case .empty, .binary, .unsupported:
            ContentUnavailableView(
                documentTitle(for: document.kind),
                systemImage: systemImage(for: document.kind),
                description: Text(document.message ?? "暂无可展示内容")
            )
            .foregroundStyle(NativeTheme.textSecondary)
        }
    }

    private var sideBySideDiffContent: some View {
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
    }

    private var unifiedDiffContent: some View {
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

func editorDisplayLineCount(_ text: String) -> Int {
    guard !text.isEmpty else {
        return 1
    }
    var lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
    if text.hasSuffix("\n"), lines > 1 {
        lines -= 1
    }
    return max(lines, 1)
}
