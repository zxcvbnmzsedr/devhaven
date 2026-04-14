import SwiftUI
import DevHavenCore

struct WorkspaceEditorTabView: View {
    @Bindable var viewModel: NativeAppViewModel
    let projectPath: String
    let tabID: String

    @State private var editorCommandRouter = WorkspaceEditorCommandRouter()
    @State private var codeEditBridge = WorkspaceCodeEditEditorBridge()
    @State private var goToLineDraft = ""
    @State private var isGoToLinePresented = false

    var body: some View {
        if let tab = viewModel.workspaceEditorTabState(for: projectPath, tabID: tabID) {
            VStack(spacing: 0) {
                header(for: tab)
                Divider()
                content(for: tab)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(NativeTheme.window)
            .focusedSceneValue(\.workspaceEditorCommandRouter, editorCommandRouter)
            .focusedSceneValue(
                \.workspaceEditorCommandsEnabled,
                tab.kind == .text && viewModel.workspaceFocusedArea == .editorTab(tabID)
            )
            .task(id: tabID) {
                syncEditorCommandRouter()
            }
            .onChange(of: tab.kind) { _, _ in
                syncEditorCommandRouter()
            }
            .sheet(isPresented: $isGoToLinePresented) {
                goToLineSheet
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
                WorkspaceCodeEditEditorView(
                    filePath: tab.filePath,
                    text: Binding(
                        get: {
                            viewModel.workspaceEditorTabState(for: projectPath, tabID: tabID)?.text ?? tab.text
                        },
                        set: { nextText in
                            viewModel.updateWorkspaceEditorText(nextText, tabID: tabID, in: projectPath)
                        }
                    ),
                    isEditable: tab.isEditable,
                    shouldRequestFocus: viewModel.workspaceFocusedArea == .editorTab(tabID),
                    displayOptions: viewModel.workspaceEditorDisplayOptions,
                    bridge: codeEditBridge
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

            Button("查找") {
                codeEditBridge.showFindPanel()
            }
            .buttonStyle(.borderless)
            .disabled(tab.kind != .text)

            Button("替换") {
                codeEditBridge.showReplacePanel()
            }
            .buttonStyle(.borderless)
            .disabled(tab.kind != .text || !tab.isEditable)

            editorDisplayOptionsMenu
                .disabled(tab.kind != .text)

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

    private var goToLineSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("跳转到行")
                .font(.headline)
                .foregroundStyle(NativeTheme.textPrimary)

            TextField("输入 1 开始的行号", text: $goToLineDraft)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
                .onSubmit {
                    confirmGoToLine()
                }

            HStack {
                Spacer()
                Button("取消") {
                    isGoToLinePresented = false
                }
                Button("跳转") {
                    confirmGoToLine()
                }
                .buttonStyle(.borderedProminent)
                .disabled(Int(goToLineDraft) == nil)
            }
        }
        .padding(20)
        .frame(width: 320)
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

    private var editorDisplayOptionsMenu: some View {
        Menu {
            Toggle(isOn: Binding(
                get: { viewModel.workspaceEditorDisplayOptions.showsLineNumbers },
                set: { value in
                    updateDisplayOptions { options in
                        options.showsLineNumbers = value
                    }
                }
            )) {
                Label("显示行号", systemImage: "list.number")
            }

            Toggle(isOn: Binding(
                get: { viewModel.workspaceEditorDisplayOptions.highlightsCurrentLine },
                set: { value in
                    updateDisplayOptions { options in
                        options.highlightsCurrentLine = value
                    }
                }
            )) {
                Label("高亮当前行", systemImage: "highlighter")
            }

            Toggle(isOn: Binding(
                get: { viewModel.workspaceEditorDisplayOptions.usesSoftWraps },
                set: { value in
                    updateDisplayOptions { options in
                        options.usesSoftWraps = value
                    }
                }
            )) {
                Label("软换行", systemImage: "text.justify.left")
            }

            Toggle(isOn: Binding(
                get: { viewModel.workspaceEditorDisplayOptions.showsWhitespaceCharacters },
                set: { value in
                    updateDisplayOptions { options in
                        options.showsWhitespaceCharacters = value
                    }
                }
            )) {
                Label("显示空白字符", systemImage: "space")
            }

            Toggle(isOn: Binding(
                get: { viewModel.workspaceEditorDisplayOptions.showsRightMargin },
                set: { value in
                    updateDisplayOptions { options in
                        options.showsRightMargin = value
                    }
                }
            )) {
                Label("显示右边界", systemImage: "ruler")
            }
        } label: {
            Label("显示", systemImage: "slider.horizontal.3")
                .labelStyle(.titleAndIcon)
        }
        .menuStyle(.borderlessButton)
        .help("编辑器显示选项")
    }

    private func confirmGoToLine() {
        guard let lineNumber = Int(goToLineDraft), lineNumber > 0 else {
            return
        }
        codeEditBridge.goToLine(lineNumber)
        isGoToLinePresented = false
    }

    private func syncEditorCommandRouter() {
        editorCommandRouter.startSearchAction = {
            codeEditBridge.showFindPanel()
        }
        editorCommandRouter.showReplaceAction = {
            codeEditBridge.showReplacePanel()
        }
        editorCommandRouter.navigateSearchNextAction = {
            codeEditBridge.findNext()
        }
        editorCommandRouter.navigateSearchPreviousAction = {
            codeEditBridge.findPrevious()
        }
        editorCommandRouter.useSelectionForSearchAction = {
            codeEditBridge.useSelectionForFind()
        }
        editorCommandRouter.closeSearchAction = {
            codeEditBridge.hideFindPanel()
        }
        editorCommandRouter.goToLineAction = {
            isGoToLinePresented = true
        }
        editorCommandRouter.saveAction = {
            viewModel.saveWorkspaceEditorTab(tabID, in: projectPath)
        }
        editorCommandRouter.reloadAction = {
            viewModel.reloadWorkspaceEditorTab(tabID, in: projectPath)
        }
    }

    private func updateDisplayOptions(_ mutate: (inout WorkspaceEditorDisplayOptions) -> Void) {
        var nextOptions = viewModel.workspaceEditorDisplayOptions
        mutate(&nextOptions)
        viewModel.updateWorkspaceEditorDisplayOptions(nextOptions)
    }

}
