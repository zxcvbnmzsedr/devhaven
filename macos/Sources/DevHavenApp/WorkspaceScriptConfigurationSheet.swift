import SwiftUI
import DevHavenCore

struct WorkspaceScriptConfigurationSheet: View {
    private let store = LegacyCompatStore()

    let viewModel: NativeAppViewModel
    let project: Project
    let onManageSharedScripts: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var scripts: [ProjectScript]
    @State private var selectedScriptID: String?
    @State private var selectedSharedScriptID = ""
    @State private var sharedScripts = [SharedScriptEntry]()
    @State private var sharedScriptsError: String?
    @State private var validationError: String?
    @State private var isLoadingSharedScripts = false
    @State private var isSaving = false

    init(
        viewModel: NativeAppViewModel,
        project: Project,
        onManageSharedScripts: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.project = project
        self.onManageSharedScripts = onManageSharedScripts
        _scripts = State(initialValue: project.scripts)
        _selectedScriptID = State(initialValue: project.scripts.first?.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            HStack(alignment: .top, spacing: 16) {
                leftPanel
                rightPanel
            }

            footer
        }
        .padding(20)
        .frame(minWidth: 980, minHeight: 640)
        .background(NativeTheme.window)
        .task {
            loadSharedScripts()
        }
        .onChange(of: selectedScriptID) { _, _ in
            selectedSharedScriptID = ""
            validationError = nil
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("脚本配置")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(NativeTheme.textPrimary)
                    Text("运行菜单只消费当前项目的 `Project.scripts`；通用脚本仅作为配置阶段的模板来源。")
                        .font(.caption)
                        .foregroundStyle(NativeTheme.textSecondary)
                }
                Spacer()
                Button("管理通用脚本") {
                    dismiss()
                    onManageSharedScripts()
                }
                .buttonStyle(.bordered)
            }

            Text(project.path)
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
                    Text("项目脚本")
                        .font(.headline)
                        .foregroundStyle(NativeTheme.textPrimary)
                    Text("\(scripts.count) 个配置")
                        .font(.caption)
                        .foregroundStyle(NativeTheme.textSecondary)
                }
                Spacer()
                Button("新增脚本") {
                    addScript()
                }
                .buttonStyle(.borderedProminent)
                .tint(NativeTheme.accent)
            }

            ScrollView {
                VStack(spacing: 8) {
                    if scripts.isEmpty {
                        placeholder("暂无脚本，点击右上角创建。")
                    } else {
                        ForEach(scripts) { script in
                            Button {
                                selectedScriptID = script.id
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(script.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名脚本" : script.name)
                                        .font(.headline)
                                        .foregroundStyle(NativeTheme.textPrimary)
                                        .lineLimit(1)
                                    Text(script.start.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "尚未填写命令" : script.start)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(NativeTheme.textSecondary)
                                        .lineLimit(2)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(selectedScriptID == script.id ? NativeTheme.accent.opacity(0.14) : NativeTheme.elevated)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(selectedScriptID == script.id ? NativeTheme.accent.opacity(0.75) : NativeTheme.border, lineWidth: 1)
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
            if let selectedIndex {
                editorCard(for: selectedIndex)
            } else {
                placeholder("请选择一个脚本开始编辑。")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func editorCard(for index: Int) -> some View {
        let script = scripts[index]
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(script.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名脚本" : script.name)
                        .font(.headline)
                        .foregroundStyle(NativeTheme.textPrimary)
                    Text("脚本 ID：\(script.id)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(NativeTheme.textSecondary)
                        .textSelection(.enabled)
                }
                Spacer()
                Button("删除当前脚本", role: .destructive) {
                    removeSelectedScript(index: index)
                }
                .buttonStyle(.bordered)
            }

            labeledField(title: "插入通用脚本（可选）") {
                Picker("插入通用脚本（可选）", selection: $selectedSharedScriptID) {
                    Text("手动输入命令").tag("")
                    ForEach(sharedScripts) { entry in
                        Text("\(entry.name) (\(entry.relativePath))").tag(entry.id)
                    }
                }
                .pickerStyle(.menu)
                .tint(NativeTheme.textPrimary)
                .onChange(of: selectedSharedScriptID) { _, newValue in
                    applySharedScriptSelection(newValue, index: index)
                }

                if isLoadingSharedScripts {
                    Text("正在加载通用脚本…")
                        .font(.caption2)
                        .foregroundStyle(NativeTheme.textSecondary)
                }
                if let sharedScriptsError {
                    Text(sharedScriptsError)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }

            labeledField(title: "名称") {
                TextField(
                    "例如：日志查看",
                    text: Binding(
                        get: { scripts[index].name },
                        set: {
                            scripts[index].name = $0
                            validationError = nil
                        }
                    )
                )
                .textFieldStyle(.plain)
                .foregroundStyle(NativeTheme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(NativeTheme.elevated)
                .clipShape(.rect(cornerRadius: 12))
            }

            labeledField(title: "启动命令") {
                TextEditor(text: Binding(
                    get: { scripts[index].start },
                    set: { updateCommand($0, index: index) }
                ))
                .font(.body.monospaced())
                .foregroundStyle(NativeTheme.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 140)
                .padding(10)
                .background(NativeTheme.elevated)
                .clipShape(.rect(cornerRadius: 12))
            }

            if !scripts[index].paramSchema.isEmpty {
                parameterSection(index: index)
            }

            if let validationError {
                Text(validationError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(16)
        .background(NativeTheme.surface)
        .clipShape(.rect(cornerRadius: 16))
    }

    private func parameterSection(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("参数配置")
                .font(.headline)
                .foregroundStyle(NativeTheme.textPrimary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                ForEach(scripts[index].paramSchema) { field in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(field.required ? "\(field.label) *" : field.label)
                            .font(.caption)
                            .foregroundStyle(NativeTheme.textSecondary)
                        TextField(
                            field.defaultValue ?? "请输入 \(field.label)",
                            text: Binding(
                                get: { scripts[index].templateParams[field.key] ?? "" },
                                set: { updateTemplateParam($0, key: field.key, index: index) }
                            )
                        )
                        .textFieldStyle(.plain)
                        .foregroundStyle(NativeTheme.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(NativeTheme.elevated)
                        .clipShape(.rect(cornerRadius: 12))

                        if let description = field.description,
                           !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(description)
                                .font(.caption2)
                                .foregroundStyle(NativeTheme.textSecondary)
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text("保存后会直接写回当前项目的 `Project.scripts`，运行菜单会立刻刷新。")
                .font(.caption)
                .foregroundStyle(NativeTheme.textSecondary)
            Spacer()
            Button("取消") {
                dismiss()
            }
            .buttonStyle(.bordered)

            Button(isSaving ? "保存中..." : "保存并关闭") {
                saveScripts()
            }
            .buttonStyle(.borderedProminent)
            .tint(NativeTheme.accent)
            .disabled(isSaving)
        }
    }

    private var selectedIndex: Int? {
        if let selectedScriptID,
           let index = scripts.firstIndex(where: { $0.id == selectedScriptID }) {
            return index
        }
        return scripts.indices.first
    }

    private func labeledField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(NativeTheme.textSecondary)
            content()
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(NativeTheme.textSecondary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NativeTheme.elevated)
            .clipShape(.rect(cornerRadius: 12))
    }

    private func addScript() {
        let script = ProjectScript(id: UUID().uuidString.lowercased(), name: "", start: "")
        scripts.append(script)
        selectedScriptID = script.id
        selectedSharedScriptID = ""
        validationError = nil
    }

    private func removeSelectedScript(index: Int) {
        scripts.remove(at: index)
        selectedScriptID = scripts.indices.contains(index) ? scripts[index].id : scripts.last?.id
        validationError = nil
    }

    private func updateCommand(_ value: String, index: Int) {
        let schema = ScriptTemplateSupport.mergeParamSchema(command: value, schema: scripts[index].paramSchema)
        let templateParams = ScriptTemplateSupport.buildTemplateParams(
            schema: schema,
            explicitValues: scripts[index].templateParams
        )
        scripts[index].start = value
        scripts[index].paramSchema = schema
        scripts[index].templateParams = templateParams
        validationError = nil
    }

    private func updateTemplateParam(_ value: String, key: String, index: Int) {
        scripts[index].templateParams[key] = value
        validationError = nil
    }

    private func applySharedScriptSelection(_ sharedScriptID: String, index: Int) {
        guard !sharedScriptID.isEmpty else {
            validationError = nil
            return
        }
        guard let entry = sharedScripts.first(where: { $0.id == sharedScriptID }) else {
            sharedScriptsError = "通用脚本不存在或已失效。"
            return
        }

        let start = ScriptTemplateSupport.applySharedScriptTemplate(
            commandTemplate: entry.commandTemplate,
            absolutePath: entry.absolutePath
        )
        let paramSchema = ScriptTemplateSupport.mergeParamSchema(command: start, schema: entry.params)
        let templateParams = ScriptTemplateSupport.buildTemplateParams(
            schema: paramSchema,
            explicitValues: scripts[index].templateParams
        )
        if scripts[index].name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            scripts[index].name = entry.name
        }
        scripts[index].start = start
        scripts[index].paramSchema = paramSchema
        scripts[index].templateParams = templateParams
        validationError = nil
    }

    private func loadSharedScripts() {
        isLoadingSharedScripts = true
        defer { isLoadingSharedScripts = false }
        do {
            sharedScripts = try store.listSharedScripts(rootOverride: viewModel.snapshot.appState.settings.sharedScriptsRoot)
            sharedScriptsError = nil
        } catch {
            sharedScripts = []
            sharedScriptsError = error.localizedDescription
        }
    }

    private func saveScripts() {
        isSaving = true
        defer { isSaving = false }
        do {
            try viewModel.saveWorkspaceScripts(validatedScripts(), in: project.path)
            dismiss()
        } catch {
            validationError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func validatedScripts() throws -> [ProjectScript] {
        var seenIDs = Set<String>()
        return try scripts.enumerated().map { offset, script in
            let name = script.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                throw validationError("第 \(offset + 1) 个脚本名称不能为空。")
            }
            guard seenIDs.insert(script.id).inserted else {
                throw validationError("检测到重复脚本 ID：\(script.id)")
            }

            let start = ScriptTemplateSupport.normalizeShellTemplateText(script.start)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !start.isEmpty else {
                throw validationError("脚本 “\(name)” 的启动命令不能为空。")
            }

            let paramSchema = ScriptTemplateSupport.mergeParamSchema(command: start, schema: script.paramSchema)
            let templateParams = ScriptTemplateSupport.buildTemplateParams(
                schema: paramSchema,
                explicitValues: script.templateParams
            )
            let resolution = ScriptTemplateSupport.resolveCommand(
                template: start,
                paramSchema: paramSchema,
                explicitValues: templateParams
            )
            if !resolution.missingRequiredKeys.isEmpty {
                throw validationError("脚本 “\(name)” 缺少必填参数：\(resolution.missingRequiredKeys.joined(separator: "、"))")
            }

            return ProjectScript(
                id: script.id,
                name: name,
                start: start,
                paramSchema: paramSchema,
                templateParams: paramSchema.isEmpty ? [:] : templateParams
            )
        }
    }

    private func validationError(_ message: String) -> NSError {
        NSError(
            domain: "DevHavenApp.WorkspaceScriptConfiguration",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
