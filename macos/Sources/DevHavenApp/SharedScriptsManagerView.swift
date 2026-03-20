import SwiftUI
import AppKit
import DevHavenCore

struct SharedScriptsManagerView: View {
    private let store = LegacyCompatStore()
    let root: String

    @State private var scripts: [SharedScriptManifestScript] = []
    @State private var selectedScriptId: String?
    @State private var scriptFilter = ""
    @State private var scriptContent = ""
    @State private var scriptContentSnapshot = ""
    @State private var isLoading = false
    @State private var isSavingManifest = false
    @State private var isSavingContent = false
    @State private var isRestoringPresets = false
    @State private var manifestMessage: String?
    @State private var manifestError: String?
    @State private var scriptContentMessage: String?
    @State private var scriptContentError: String?
    @State private var createScriptState: CreateScriptState?

    var body: some View {
        VStack(spacing: 14) {
            header

            HStack(alignment: .top, spacing: 14) {
                leftPanel
                rightPanel
            }
        }
        .sheet(item: $createScriptState) { state in
            SharedScriptCreateSheet(
                state: state,
                existingIds: Set(scripts.map(\.id)),
                existingPaths: Set(scripts.map(\.path)),
                onCancel: { createScriptState = nil },
                onConfirm: { createdScript in
                    scripts.append(createdScript)
                    selectedScriptId = createdScript.id
                    createScriptState = nil
                    manifestMessage = "已新增脚本，请记得保存清单。"
                    manifestError = nil
                }
            )
            .preferredColorScheme(.dark)
        }
        .task {
            guard scripts.isEmpty else { return }
            await loadScripts()
        }
        .onChange(of: selectedScriptId) { _, _ in
            loadSelectedScriptContent()
        }
    }

    private var selectedScriptIndex: Int? {
        scripts.firstIndex { $0.id == selectedScriptId }
    }

    private var selectedScript: SharedScriptManifestScript? {
        selectedScriptIndex.flatMap { scripts[$0] }
    }

    private var filteredScripts: [SharedScriptManifestScript] {
        let query = scriptFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return scripts }
        return scripts.filter { script in
            script.id.lowercased().contains(query)
                || script.name.lowercased().contains(query)
                || script.path.lowercased().contains(query)
        }
    }

    private var isManifestDirty: Bool {
        manifestMessage == "已新增脚本，请记得保存清单。"
            || manifestMessage == "脚本参数或定义已修改，请保存清单。"
            || manifestMessage == "已删除脚本，请保存清单。"
    }

    private var isScriptContentDirty: Bool {
        scriptContent != scriptContentSnapshot
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("通用脚本管理")
                        .font(.headline)
                        .foregroundStyle(NativeTheme.textPrimary)
                    Text("直接读写 `manifest.json` 与脚本文件，保持与 Tauri 版数据兼容。")
                        .font(.caption)
                        .foregroundStyle(NativeTheme.textSecondary)
                }
                Spacer()
                Button("打开目录") {
                    openScriptsDirectory()
                }
                .buttonStyle(.bordered)
            }

            Text("根目录：\(root)")
                .font(.caption.monospaced())
                .foregroundStyle(NativeTheme.textSecondary)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NativeTheme.elevated)
                .clipShape(.rect(cornerRadius: 12))
        }
    }

    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("脚本清单")
                        .font(.headline)
                        .foregroundStyle(NativeTheme.textPrimary)
                    Text("\(filteredScripts.count)/\(scripts.count) 个脚本")
                        .font(.caption)
                        .foregroundStyle(NativeTheme.textSecondary)
                }
                Spacer()
                Button("新增脚本") {
                    createScriptState = .init()
                }
                .buttonStyle(.borderedProminent)
                .tint(NativeTheme.accent)
            }

            TextField("按名称 / ID / 路径搜索", text: $scriptFilter)
                .textFieldStyle(.plain)
                .foregroundStyle(NativeTheme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(NativeTheme.elevated)
                .clipShape(.rect(cornerRadius: 12))

            ScrollView {
                VStack(spacing: 8) {
                    if isLoading {
                        statusPlaceholder("加载中...")
                    } else if filteredScripts.isEmpty {
                        statusPlaceholder(scripts.isEmpty ? "暂无脚本，点击右上角创建。" : "没有匹配结果。")
                    } else {
                        ForEach(filteredScripts) { script in
                            Button {
                                selectedScriptId = script.id
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(script.name.isEmpty ? script.id : script.name)
                                            .font(.headline)
                                            .foregroundStyle(NativeTheme.textPrimary)
                                            .lineLimit(1)
                                        Spacer()
                                        Text("\(script.params.count) 参数")
                                            .font(.caption2)
                                            .foregroundStyle(NativeTheme.textSecondary)
                                    }
                                    Text("ID：\(script.id)")
                                        .font(.caption2)
                                        .foregroundStyle(NativeTheme.textSecondary)
                                        .lineLimit(1)
                                    Text(script.path)
                                        .font(.caption2)
                                        .foregroundStyle(NativeTheme.textSecondary)
                                        .lineLimit(1)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(selectedScriptId == script.id ? NativeTheme.accent.opacity(0.14) : NativeTheme.elevated)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(selectedScriptId == script.id ? NativeTheme.accent.opacity(0.75) : NativeTheme.border, lineWidth: 1)
                                )
                                .clipShape(.rect(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .frame(width: 300)
    }

    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let selectedScript, let selectedScriptIndex {
                scriptDefinitionCard(script: selectedScript, index: selectedScriptIndex)
                paramsCard(script: selectedScript, index: selectedScriptIndex)
                scriptContentCard(script: selectedScript)
                footerActions
            } else {
                statusPlaceholder("请选择一个脚本开始编辑。")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func scriptDefinitionCard(script: SharedScriptManifestScript, index: Int) -> some View {
        settingsPanel(title: "脚本定义", description: "ID 与相对路径创建后锁定，名称与命令模板可继续编辑。") {
            HStack(spacing: 12) {
                lockedField(title: "ID", value: script.id)
                lockedField(title: "脚本相对路径", value: script.path)
            }

            HStack(spacing: 12) {
                editableField(title: "名称", text: Binding(
                    get: { scripts[index].name },
                    set: { updateScript(index: index) { $0.name = $1 }($0) }
                ))

                VStack(alignment: .leading, spacing: 6) {
                    Text("命令模板")
                        .font(.caption)
                        .foregroundStyle(NativeTheme.textSecondary)
                    TextEditor(text: Binding(
                        get: { scripts[index].commandTemplate },
                        set: { updateScript(index: index) { $0.commandTemplate = $1 }($0) }
                    ))
                    .font(.body.monospaced())
                    .foregroundStyle(NativeTheme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 92)
                    .padding(10)
                    .background(NativeTheme.elevated)
                    .clipShape(.rect(cornerRadius: 12))
                }
            }
        }
    }

    private func paramsCard(script: SharedScriptManifestScript, index: Int) -> some View {
        settingsPanel(title: "参数定义", description: "对齐 Tauri 的参数模型，支持 key / label / 类型 / 默认值 / 描述。") {
            if script.params.isEmpty {
                statusPlaceholder("当前没有参数。")
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(script.params.enumerated()), id: \.offset) { paramIndex, _ in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("参数 \(paramIndex + 1)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(NativeTheme.textSecondary)
                                Spacer()
                                Button("移除", role: .destructive) {
                                    scripts[index].params.remove(at: paramIndex)
                                    markManifestDirty("脚本参数或定义已修改，请保存清单。")
                                }
                                .buttonStyle(.bordered)
                            }

                            HStack(spacing: 12) {
                                editableField(title: "Key", text: Binding(
                                    get: { scripts[index].params[paramIndex].key },
                                    set: { scripts[index].params[paramIndex].key = $0; markManifestDirty("脚本参数或定义已修改，请保存清单。") }
                                ))
                                editableField(title: "Label", text: Binding(
                                    get: { scripts[index].params[paramIndex].label },
                                    set: { scripts[index].params[paramIndex].label = $0; markManifestDirty("脚本参数或定义已修改，请保存清单。") }
                                ))
                            }

                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("类型")
                                        .font(.caption)
                                        .foregroundStyle(NativeTheme.textSecondary)
                                    Picker("类型", selection: Binding(
                                        get: { scripts[index].params[paramIndex].type },
                                        set: { scripts[index].params[paramIndex].type = $0; markManifestDirty("脚本参数或定义已修改，请保存清单。") }
                                    )) {
                                        Text("文本").tag(ScriptParamFieldType.text)
                                        Text("数字").tag(ScriptParamFieldType.number)
                                        Text("密文").tag(ScriptParamFieldType.secret)
                                    }
                                    .pickerStyle(.segmented)
                                }

                                editableField(title: "默认值", text: Binding(
                                    get: { scripts[index].params[paramIndex].defaultValue ?? "" },
                                    set: {
                                        scripts[index].params[paramIndex].defaultValue = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
                                        markManifestDirty("脚本参数或定义已修改，请保存清单。")
                                    }
                                ))
                            }

                            HStack {
                                Toggle("必填", isOn: Binding(
                                    get: { scripts[index].params[paramIndex].required },
                                    set: { scripts[index].params[paramIndex].required = $0; markManifestDirty("脚本参数或定义已修改，请保存清单。") }
                                ))
                                .toggleStyle(.checkbox)
                                .foregroundStyle(NativeTheme.textPrimary)
                                Spacer()
                            }

                            editableField(title: "描述", text: Binding(
                                get: { scripts[index].params[paramIndex].description ?? "" },
                                set: {
                                    scripts[index].params[paramIndex].description = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
                                    markManifestDirty("脚本参数或定义已修改，请保存清单。")
                                }
                            ))
                        }
                        .padding(14)
                        .background(NativeTheme.elevated)
                        .clipShape(.rect(cornerRadius: 14))
                    }
                }
            }

            HStack {
                Spacer()
                Button("添加参数") {
                    scripts[index].params.append(
                        ScriptParamField(
                            key: "",
                            label: "",
                            type: .text,
                            required: false,
                            defaultValue: nil,
                            description: nil
                        )
                    )
                    markManifestDirty("脚本参数或定义已修改，请保存清单。")
                }
                .buttonStyle(.borderedProminent)
                .tint(NativeTheme.accent)
            }
        }
    }

    private func scriptContentCard(script: SharedScriptManifestScript) -> some View {
        settingsPanel(title: "脚本文件内容", description: "直接编辑并保存对应脚本文件。") {
            TextEditor(text: $scriptContent)
                .font(.body.monospaced())
                .foregroundStyle(NativeTheme.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 240)
                .padding(10)
                .background(NativeTheme.elevated)
                .clipShape(.rect(cornerRadius: 12))

            if let scriptContentError {
                Text(scriptContentError)
                    .font(.caption)
                    .foregroundStyle(NativeTheme.danger)
            } else if let scriptContentMessage {
                Text(scriptContentMessage)
                    .font(.caption)
                    .foregroundStyle(NativeTheme.success)
            }
        }
    }

    private var footerActions: some View {
        HStack(spacing: 12) {
            Button("删除当前脚本", role: .destructive) {
                guard let selectedScriptId else { return }
                scripts.removeAll { $0.id == selectedScriptId }
                self.selectedScriptId = scripts.first?.id
                markManifestDirty("已删除脚本，请保存清单。")
            }
            .buttonStyle(.bordered)

            Button(isRestoringPresets ? "恢复中..." : "恢复内置预设") {
                Task { await restorePresets() }
            }
            .buttonStyle(.bordered)
            .disabled(isRestoringPresets)

            Spacer()

            Button(isSavingManifest ? "保存中..." : "保存清单") {
                Task { await saveManifest() }
            }
            .buttonStyle(.borderedProminent)
            .tint(NativeTheme.accent)
            .disabled(isSavingManifest || scripts.isEmpty == false && !hasValidSelectionState)

            Button(isSavingContent ? "保存中..." : "保存脚本文件") {
                Task { await saveSelectedScriptContent() }
            }
            .buttonStyle(.borderedProminent)
            .tint(NativeTheme.accent)
            .disabled(isSavingContent || selectedScript == nil || !isScriptContentDirty)
        }
        .overlay(alignment: .bottomLeading) {
            if let manifestError {
                Text(manifestError)
                    .font(.caption)
                    .foregroundStyle(NativeTheme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .offset(y: 26)
            } else if let manifestMessage {
                Text(manifestMessage)
                    .font(.caption)
                    .foregroundStyle(NativeTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .offset(y: 26)
            }
        }
        .padding(.bottom, 22)
    }

    private var hasValidSelectionState: Bool {
        scripts.allSatisfy { !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func settingsPanel<Content: View>(title: String, description: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(NativeTheme.textPrimary)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(NativeTheme.textSecondary)
            }
            content()
        }
        .padding(18)
        .background(NativeTheme.window)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(NativeTheme.border, lineWidth: 1)
        )
        .clipShape(.rect(cornerRadius: 16))
    }

    private func lockedField(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(NativeTheme.textSecondary)
            Text(value)
                .font(.body.monospaced())
                .foregroundStyle(NativeTheme.textSecondary)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        .foregroundStyle(NativeTheme.border)
                )
                .clipShape(.rect(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func editableField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(NativeTheme.textSecondary)
            TextField(title, text: text)
                .textFieldStyle(.plain)
                .foregroundStyle(NativeTheme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(NativeTheme.elevated)
                .clipShape(.rect(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusPlaceholder(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(NativeTheme.textSecondary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NativeTheme.elevated)
            .clipShape(.rect(cornerRadius: 12))
    }

    private func updateScript(index: Int, setter: @escaping (inout SharedScriptManifestScript, String) -> Void) -> (String) -> Void {
        { newValue in
            setter(&scripts[index], newValue)
            markManifestDirty("脚本参数或定义已修改，请保存清单。")
        }
    }

    private func markManifestDirty(_ message: String) {
        manifestMessage = message
        manifestError = nil
    }

    private func openScriptsDirectory() {
        let resolved = resolveHomePath(root)
        NSWorkspace.shared.open(URL(fileURLWithPath: resolved, isDirectory: true))
    }

    private func resolveHomePath(_ path: String) -> String {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        if path == "~" { return homePath }
        if path.hasPrefix("~/") {
            return homePath + "/" + String(path.dropFirst(2))
        }
        return path
    }

    @MainActor
    private func loadScripts() async {
        isLoading = true
        manifestError = nil
        do {
            let entries = try store.listSharedScripts(rootOverride: root)
            scripts = entries.map {
                SharedScriptManifestScript(
                    id: $0.id,
                    name: $0.name,
                    path: $0.relativePath,
                    commandTemplate: $0.commandTemplate,
                    params: $0.params
                )
            }
            selectedScriptId = scripts.first?.id
            manifestMessage = nil
        } catch {
            manifestError = error.localizedDescription
            scripts = []
            selectedScriptId = nil
        }
        isLoading = false
        loadSelectedScriptContent()
    }

    private func loadSelectedScriptContent() {
        guard let selectedScript else {
            scriptContent = ""
            scriptContentSnapshot = ""
            scriptContentError = nil
            scriptContentMessage = nil
            return
        }
        do {
            let content = try store.readSharedScriptFile(relativePath: selectedScript.path, rootOverride: root)
            scriptContent = content
            scriptContentSnapshot = content
            scriptContentError = nil
            scriptContentMessage = nil
        } catch {
            scriptContent = ""
            scriptContentSnapshot = ""
            scriptContentError = "脚本文件不存在，保存后会自动创建。"
            scriptContentMessage = nil
        }
    }

    @MainActor
    private func saveManifest() async {
        isSavingManifest = true
        defer { isSavingManifest = false }

        do {
            try store.saveSharedScriptsManifest(scripts, rootOverride: root)
            manifestMessage = "脚本清单已保存。"
            manifestError = nil
            await loadScripts()
        } catch {
            manifestError = error.localizedDescription
        }
    }

    @MainActor
    private func restorePresets() async {
        isRestoringPresets = true
        defer { isRestoringPresets = false }

        do {
            let result = try store.restoreSharedScriptPresets(rootOverride: root)
            manifestMessage = "内置预设已同步：新增 \(result.addedScripts) 项，补齐文件 \(result.createdFiles) 个。"
            manifestError = nil
            await loadScripts()
        } catch {
            manifestError = error.localizedDescription
        }
    }

    @MainActor
    private func saveSelectedScriptContent() async {
        guard let selectedScript else { return }
        isSavingContent = true
        defer { isSavingContent = false }

        do {
            try store.writeSharedScriptFile(relativePath: selectedScript.path, content: scriptContent, rootOverride: root)
            scriptContentSnapshot = scriptContent
            scriptContentMessage = "脚本文件已保存。"
            scriptContentError = nil
        } catch {
            scriptContentError = error.localizedDescription
            scriptContentMessage = nil
        }
    }
}

private func normalizeSharedScriptRelativePath(_ path: String) -> String? {
    let components = path
        .split(separator: "/")
        .flatMap { $0.split(separator: "\\") }
        .map(String.init)
        .filter { !$0.isEmpty && $0 != "." }
    guard !components.isEmpty, !components.contains("..") else {
        return nil
    }
    return components.joined(separator: "/")
}

private struct CreateScriptState: Identifiable {
    let id = UUID()
}

private struct SharedScriptCreateSheet: View {
    @Environment(\.dismiss) private var dismiss

    let state: CreateScriptState
    let existingIds: Set<String>
    let existingPaths: Set<String>
    let onCancel: () -> Void
    let onConfirm: (SharedScriptManifestScript) -> Void

    @State private var scriptId = ""
    @State private var scriptName = ""
    @State private var scriptPath = ""
    @State private var usePathAsId = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("新增通用脚本")
                .font(.title3.weight(.semibold))
                .foregroundStyle(NativeTheme.textPrimary)

            VStack(alignment: .leading, spacing: 10) {
                labeledInput(title: "脚本相对路径", text: $scriptPath, placeholder: "例如 ops/deploy.sh")

                Toggle("ID 使用路径（推荐）", isOn: $usePathAsId)
                    .toggleStyle(.checkbox)
                    .foregroundStyle(NativeTheme.textPrimary)

                if !usePathAsId {
                    labeledInput(title: "脚本 ID", text: $scriptId, placeholder: "例如 deploy")
                }

                labeledInput(title: "脚本名称", text: $scriptName, placeholder: "例如 Jenkins 部署")
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(NativeTheme.danger)
            }

            HStack {
                Spacer()
                Button("取消") {
                    onCancel()
                    dismiss()
                }
                Button("创建") {
                    createScript()
                }
                .buttonStyle(.borderedProminent)
                .tint(NativeTheme.accent)
            }
        }
        .padding(22)
        .frame(minWidth: 460)
    }

    private func labeledInput(title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(NativeTheme.textSecondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .foregroundStyle(NativeTheme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(NativeTheme.elevated)
                .clipShape(.rect(cornerRadius: 12))
        }
    }

    private func createScript() {
        guard let normalizedPath = normalizeSharedScriptRelativePath(scriptPath) else {
            errorMessage = "脚本相对路径不合法。"
            return
        }

        let resolvedId = (usePathAsId ? normalizedPath : scriptId).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedId.isEmpty else {
            errorMessage = "脚本 ID 不能为空。"
            return
        }
        guard !existingIds.contains(resolvedId) else {
            errorMessage = "脚本 ID 已存在：\(resolvedId)"
            return
        }
        guard !existingPaths.contains(normalizedPath) else {
            errorMessage = "脚本路径已存在：\(normalizedPath)"
            return
        }

        let resolvedName = scriptName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? URL(fileURLWithPath: normalizedPath).deletingPathExtension().lastPathComponent
            : scriptName.trimmingCharacters(in: .whitespacesAndNewlines)

        onConfirm(
            SharedScriptManifestScript(
                id: resolvedId,
                name: resolvedName,
                path: normalizedPath,
                commandTemplate: "bash \"${scriptPath}\"",
                params: []
            )
        )
        dismiss()
    }
}
