import SwiftUI
import DevHavenCore

struct WorkspaceEditorTabView: View {
    @Bindable var viewModel: NativeAppViewModel
    let projectPath: String
    let tabID: String

    @State private var editorCommandRouter = WorkspaceEditorCommandRouter()
    @StateObject private var monacoBridge = WorkspaceMonacoEditorBridge()
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
                if isMarkdownRenderable(tab) {
                    markdownContent(for: tab)
                } else {
                    sourceEditorView(
                        for: tab,
                        shouldRequestFocus: viewModel.workspaceFocusedArea == .editorTab(tabID)
                    )
                }
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

            if isMarkdownRenderable(tab) {
                markdownPresentationPicker(for: tab)
                    .frame(width: 108)
            }

            Button("查找") {
                withVisibleSourceEditor {
                    monacoBridge.startSearch()
                }
            }
            .buttonStyle(.borderless)
            .disabled(tab.kind != .text)

            Button("替换") {
                withVisibleSourceEditor {
                    monacoBridge.showReplace()
                }
            }
            .buttonStyle(.borderless)
            .disabled(tab.kind != .text || !tab.isEditable)

            editorDisplayOptionsMenu
                .disabled(tab.kind != .text || isMarkdownPreviewOnly(tab))

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

    @ViewBuilder
    private func markdownContent(for tab: WorkspaceEditorTabState) -> some View {
        switch markdownPresentationMode(for: tab) {
        case .source:
            sourceEditorView(
                for: tab,
                shouldRequestFocus: viewModel.workspaceFocusedArea == .editorTab(tabID)
            )
        case .preview:
            markdownPreviewView(for: tab)
        case .split:
            WorkspaceSplitView(
                direction: .horizontal,
                ratio: markdownSplitRatio(for: tab),
                onRatioChange: { nextRatio in
                    updateMarkdownSplitRatio(nextRatio, for: tab)
                },
                onRatioChangeEnded: { nextRatio in
                    updateMarkdownSplitRatio(nextRatio, for: tab)
                },
                minLeadingSize: 320,
                minTrailingSize: 240,
                onEqualize: {
                    updateMarkdownSplitRatio(0.5, for: tab)
                }
            ) {
                sourceEditorView(
                    for: tab,
                    shouldRequestFocus: viewModel.workspaceFocusedArea == .editorTab(tabID)
                )
            } trailing: {
                markdownPreviewView(for: tab)
            }
        }
    }

    private func sourceEditorView(
        for tab: WorkspaceEditorTabState,
        shouldRequestFocus: Bool
    ) -> some View {
        WorkspaceMonacoEditorView(
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
            shouldRequestFocus: shouldRequestFocus,
            displayOptions: viewModel.workspaceEditorDisplayOptions,
            bridge: monacoBridge,
            onSaveRequested: {
                viewModel.saveWorkspaceEditorTab(tabID, in: projectPath)
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func markdownPreviewView(for tab: WorkspaceEditorTabState) -> some View {
        WorkspaceMarkdownRenderedContentView(
            content: tab.text,
            baseURL: markdownBaseURL(for: tab),
            layout: .fillAvailableSpace
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(NativeTheme.window)
    }

    private func markdownPresentationPicker(for tab: WorkspaceEditorTabState) -> some View {
        Picker(
            "",
            selection: Binding(
                get: {
                    markdownPresentationMode(for: tab)
                },
                set: { nextMode in
                    updateMarkdownPresentationMode(nextMode, for: tab)
                }
            )
        ) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .accessibilityLabel("源码")
                .tag(WorkspaceEditorMarkdownPresentationMode.source)
            Image(systemName: "doc.text.image")
                .accessibilityLabel("预览")
                .tag(WorkspaceEditorMarkdownPresentationMode.preview)
            Image(systemName: "rectangle.split.2x1")
                .accessibilityLabel("分栏")
                .tag(WorkspaceEditorMarkdownPresentationMode.split)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .help("Markdown 视图模式")
    }

    private func confirmGoToLine() {
        guard let lineNumber = Int(goToLineDraft), lineNumber > 0 else {
            return
        }
        monacoBridge.goToLine(lineNumber)
        isGoToLinePresented = false
    }

    private func syncEditorCommandRouter() {
        editorCommandRouter.startSearchAction = {
            withVisibleSourceEditor {
                monacoBridge.startSearch()
            }
        }
        editorCommandRouter.showReplaceAction = {
            withVisibleSourceEditor {
                monacoBridge.showReplace()
            }
        }
        editorCommandRouter.navigateSearchNextAction = {
            withVisibleSourceEditor {
                monacoBridge.findNext()
            }
        }
        editorCommandRouter.navigateSearchPreviousAction = {
            withVisibleSourceEditor {
                monacoBridge.findPrevious()
            }
        }
        editorCommandRouter.useSelectionForSearchAction = {
            withVisibleSourceEditor {
                monacoBridge.useSelectionForFind()
            }
        }
        editorCommandRouter.closeSearchAction = {
            monacoBridge.closeSearch()
        }
        editorCommandRouter.goToLineAction = {
            withVisibleSourceEditor {
                isGoToLinePresented = true
            }
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

    private func isMarkdownRenderable(_ tab: WorkspaceEditorTabState) -> Bool {
        tab.kind == .text && WorkspaceEditorSyntaxStyle.infer(fromFilePath: tab.filePath) == .markdown
    }

    private func isMarkdownPreviewOnly(_ tab: WorkspaceEditorTabState) -> Bool {
        isMarkdownRenderable(tab) && markdownPresentationMode(for: tab) == .preview
    }

    private func markdownPresentationMode(for tab: WorkspaceEditorTabState) -> WorkspaceEditorMarkdownPresentationMode {
        guard isMarkdownRenderable(tab) else {
            return .source
        }
        return viewModel.workspaceEditorRuntimeSession(for: projectPath, tabID: tabID).markdownPresentationMode
    }

    private func markdownSplitRatio(for tab: WorkspaceEditorTabState) -> Double {
        guard isMarkdownRenderable(tab) else {
            return 0.5
        }
        return viewModel.workspaceEditorRuntimeSession(for: projectPath, tabID: tabID).markdownSplitRatio
    }

    private func updateMarkdownPresentationMode(
        _ nextMode: WorkspaceEditorMarkdownPresentationMode,
        for tab: WorkspaceEditorTabState
    ) {
        guard isMarkdownRenderable(tab) else {
            return
        }
        var session = viewModel.workspaceEditorRuntimeSession(for: projectPath, tabID: tabID)
        session.markdownPresentationMode = nextMode
        viewModel.updateWorkspaceEditorRuntimeSession(session, tabID: tabID, in: projectPath)
    }

    private func updateMarkdownSplitRatio(_ nextRatio: Double, for tab: WorkspaceEditorTabState) {
        guard isMarkdownRenderable(tab) else {
            return
        }
        var session = viewModel.workspaceEditorRuntimeSession(for: projectPath, tabID: tabID)
        session.markdownSplitRatio = nextRatio
        viewModel.updateWorkspaceEditorRuntimeSession(session, tabID: tabID, in: projectPath)
    }

    private func markdownBaseURL(for tab: WorkspaceEditorTabState) -> URL? {
        URL(fileURLWithPath: tab.filePath).deletingLastPathComponent()
    }

    private func withVisibleSourceEditor(_ action: @escaping () -> Void) {
        guard let currentTab = viewModel.workspaceEditorTabState(for: projectPath, tabID: tabID) else {
            return
        }
        guard isMarkdownRenderable(currentTab),
              markdownPresentationMode(for: currentTab) == .preview
        else {
            action()
            return
        }

        updateMarkdownPresentationMode(.split, for: currentTab)
        DispatchQueue.main.async {
            monacoBridge.focusEditor()
            action()
        }
    }

}
