import SwiftUI
import DevHavenCore

struct WorkspaceDiffTabView: View {
    @Bindable var viewModel: WorkspaceDiffTabViewModel

    var body: some View {
        VStack(spacing: 0) {
            diffToolbar
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

    private var diffToolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.documentState.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(NativeTheme.textPrimary)
                if let document = viewModel.documentState.loadedDocument,
                   let subtitle = document.newPath ?? document.oldPath {
                    Text(subtitle)
                        .font(.caption.monospaced())
                        .foregroundStyle(NativeTheme.textSecondary)
                }
            }

            Spacer(minLength: 0)

            Picker("查看模式", selection: Binding(
                get: { viewModel.documentState.viewerMode },
                set: { viewModel.updateViewerMode($0) }
            )) {
                Text("并排").tag(WorkspaceDiffViewerMode.sideBySide)
                Text("统一").tag(WorkspaceDiffViewerMode.unified)
            }
            .pickerStyle(.segmented)
            .frame(width: 180)

            Button("刷新") {
                viewModel.refresh()
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(NativeTheme.surface)
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
