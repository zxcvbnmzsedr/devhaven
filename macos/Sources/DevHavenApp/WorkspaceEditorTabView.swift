import SwiftUI
import DevHavenCore

struct WorkspaceEditorTabView: View {
    @Bindable var viewModel: NativeAppViewModel
    let projectPath: String
    let tabID: String

    var body: some View {
        if let tab = viewModel.workspaceEditorTabState(for: projectPath, tabID: tabID) {
            VStack(spacing: 0) {
                header(for: tab)
                Divider()
                content(for: tab)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(NativeTheme.window)
            .task(id: tabID) {
                await monitorExternalChanges()
            }
        } else {
            ContentUnavailableView(
                "编辑器标签页不可用",
                systemImage: "doc.text",
                description: Text("当前文件标签页已失效，请重新从 Project 树打开。")
            )
            .foregroundStyle(NativeTheme.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func content(for tab: WorkspaceEditorTabState) -> some View {
        if tab.isLoading {
            ProgressView("正在载入文件…")
                .foregroundStyle(NativeTheme.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch tab.kind {
            case .text:
                WorkspaceTextEditorView(
                    editorID: "workspace-editor-\(tab.id)",
                    text: Binding(
                        get: {
                            viewModel.workspaceEditorTabState(for: projectPath, tabID: tabID)?.text ?? tab.text
                        },
                        set: { nextText in
                            viewModel.updateWorkspaceEditorText(nextText, tabID: tabID, in: projectPath)
                        }
                    ),
                    isEditable: tab.isEditable,
                    syntaxStyle: WorkspaceEditorSyntaxStyle.infer(fromFilePath: tab.filePath)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .binary:
                editorUnavailableContent(
                    title: "二进制文件暂不支持",
                    systemImage: "doc.fill",
                    description: tab.message ?? "基础版本暂不支持直接编辑二进制文件。"
                )
            case .unsupported:
                editorUnavailableContent(
                    title: "当前文件类型暂不支持",
                    systemImage: "doc.text.magnifyingglass",
                    description: tab.message ?? "基础版本当前仅支持 UTF-8 文本文件。"
                )
            case .missing:
                editorUnavailableContent(
                    title: "文件不存在",
                    systemImage: "exclamationmark.triangle",
                    description: tab.message ?? "该文件已被删除或移动，请关闭标签页后重新打开。"
                )
            }
        }
    }

    private func header(for tab: WorkspaceEditorTabState) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(tab.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(NativeTheme.textPrimary)
                    if tab.isDirty {
                        Text("未保存")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(.rect(cornerRadius: 999))
                    }
                    switch tab.externalChangeState {
                    case .inSync:
                        EmptyView()
                    case .modifiedOnDisk:
                        statusChip(title: "磁盘已变更", foreground: .yellow, background: .yellow.opacity(0.14))
                    case .removedOnDisk:
                        statusChip(title: "磁盘已删除", foreground: .red, background: .red.opacity(0.14))
                    }
                }
                Text(tab.filePath)
                    .font(.caption.monospaced())
                    .foregroundStyle(NativeTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                if let message = tab.message, !message.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(tab.externalChangeState == .removedOnDisk ? .red : .orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)

            Button("重新载入") {
                viewModel.reloadWorkspaceEditorTab(tabID, in: projectPath)
            }
            .buttonStyle(.borderless)
            .disabled(tab.isSaving)

            Button(tab.isSaving ? "保存中…" : "保存") {
                viewModel.saveWorkspaceEditorTab(tabID, in: projectPath)
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                tab.kind != .text
                    || !tab.isEditable
                    || !tab.isDirty
                    || tab.isSaving
                    || tab.externalChangeState == .removedOnDisk
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(NativeTheme.window)
    }

    private func editorUnavailableContent(title: String, systemImage: String, description: String) -> some View {
        ContentUnavailableView(
            title,
            systemImage: systemImage,
            description: Text(description)
        )
        .foregroundStyle(NativeTheme.textSecondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statusChip(title: String, foreground: Color, background: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(background)
            .clipShape(.rect(cornerRadius: 999))
    }

    private func monitorExternalChanges() async {
        while !Task.isCancelled {
            viewModel.checkWorkspaceEditorTabExternalChange(tabID, in: projectPath)
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }
}
