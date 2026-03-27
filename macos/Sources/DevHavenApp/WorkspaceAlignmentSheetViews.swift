import SwiftUI
import DevHavenCore

struct WorkspaceAlignmentEditorFormData: Equatable {
    var name: String
    var targetBranch: String
    var baseBranchMode: WorkspaceAlignmentBaseBranchMode
    var specifiedBaseBranch: String
    var selectedProjectPaths: Set<String>
    var applyRulesAfterSave: Bool
}

enum WorkspaceAlignmentEditorSheetMode: Equatable {
    case create
    case edit(currentProjectPaths: [String])
}

struct WorkspaceAlignmentEditorSheet: View {
    let title: String
    let mode: WorkspaceAlignmentEditorSheetMode
    let availableProjects: [Project]
    let initialData: WorkspaceAlignmentEditorFormData
    let onSubmit: (WorkspaceAlignmentEditorFormData) -> Void
    let onClose: () -> Void

    @State private var name: String
    @State private var targetBranch: String
    @State private var baseBranchMode: WorkspaceAlignmentBaseBranchMode
    @State private var specifiedBaseBranch: String
    @State private var selectedProjectPaths: Set<String>
    @State private var applyRulesAfterSave: Bool
    @State private var projectSearchQuery = ""

    init(
        title: String,
        mode: WorkspaceAlignmentEditorSheetMode,
        availableProjects: [Project],
        initialData: WorkspaceAlignmentEditorFormData,
        onSubmit: @escaping (WorkspaceAlignmentEditorFormData) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.title = title
        self.mode = mode
        self.availableProjects = availableProjects
        self.initialData = initialData
        self.onSubmit = onSubmit
        self.onClose = onClose
        _name = State(initialValue: initialData.name)
        _targetBranch = State(initialValue: initialData.targetBranch)
        _baseBranchMode = State(initialValue: initialData.baseBranchMode)
        _specifiedBaseBranch = State(initialValue: initialValueOrEmpty(initialData.specifiedBaseBranch))
        _selectedProjectPaths = State(initialValue: initialData.selectedProjectPaths)
        _applyRulesAfterSave = State(initialValue: initialData.applyRulesAfterSave)
    }

    private var sortedProjects: [Project] {
        availableProjects.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var filteredProjects: [Project] {
        filterWorkspaceAlignmentProjects(sortedProjects, query: projectSearchQuery)
    }

    private var canSubmit: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBranch = targetBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedBranch.isEmpty else {
            return false
        }
        if baseBranchMode == .specified {
            return !specifiedBaseBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.headline)
                .foregroundStyle(NativeTheme.textPrimary)

            VStack(alignment: .leading, spacing: 10) {
                fieldLabel("工作区名称")
                TextField("例如：支付链路", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 10) {
                fieldLabel("目标 branch")
                TextField("例如：feature/支付", text: $targetBranch)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 10) {
                fieldLabel("基线分支")
                Picker("基线分支", selection: $baseBranchMode) {
                    Text("自动探测").tag(WorkspaceAlignmentBaseBranchMode.autoDetect)
                    Text("指定").tag(WorkspaceAlignmentBaseBranchMode.specified)
                }
                .pickerStyle(.segmented)

                if baseBranchMode == .specified {
                    TextField("例如：develop", text: $specifiedBaseBranch)
                        .textFieldStyle(.roundedBorder)
                }
            }

            switch mode {
            case .create:
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        fieldLabel("初始项目（可选）")
                        if !sortedProjects.isEmpty {
                            helperText("已选 \(selectedProjectPaths.count) / \(sortedProjects.count)")
                        }
                    }
                    if sortedProjects.isEmpty {
                        helperText("当前没有可选项目，可以先创建空工作区，后续再添加。")
                    } else if filteredProjects.isEmpty {
                        workspaceAlignmentSearchField(text: $projectSearchQuery)
                        helperText("没有匹配的项目，换个关键词试试。")
                    } else {
                        workspaceAlignmentSearchField(text: $projectSearchQuery)
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(filteredProjects) { project in
                                    Toggle(isOn: binding(for: project.path)) {
                                        projectToggleLabel(project)
                                    }
                                    .toggleStyle(.checkbox)
                                }
                            }
                        }
                        .frame(minHeight: 120, maxHeight: 160)
                    }
                }
            case let .edit(currentProjectPaths):
                VStack(alignment: .leading, spacing: 10) {
                    fieldLabel("当前项目")
                    if currentProjectPaths.isEmpty {
                        helperText("暂无项目")
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(currentProjectPaths, id: \.self) { path in
                                Text(projectName(for: path))
                                    .foregroundStyle(NativeTheme.textPrimary)
                            }
                        }
                    }
                }
            }

            Toggle("保存后立即应用工作区规则", isOn: $applyRulesAfterSave)
                .toggleStyle(.checkbox)

            Spacer(minLength: 0)

            HStack {
                Spacer(minLength: 0)
                Button("取消", action: onClose)
                Button(primaryButtonTitle) {
                    onSubmit(
                        WorkspaceAlignmentEditorFormData(
                            name: name,
                            targetBranch: targetBranch,
                            baseBranchMode: baseBranchMode,
                            specifiedBaseBranch: specifiedBaseBranch,
                            selectedProjectPaths: selectedProjectPaths,
                            applyRulesAfterSave: applyRulesAfterSave
                        )
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)
            }
        }
        .padding(20)
        .frame(width: 460, height: mode == .create ? 560 : 400)
        .background(NativeTheme.window)
    }

    private var primaryButtonTitle: String {
        switch mode {
        case .create:
            return applyRulesAfterSave && !selectedProjectPaths.isEmpty ? "创建并应用" : "创建工作区"
        case .edit:
            return applyRulesAfterSave ? "保存并应用" : "保存"
        }
    }

    private func binding(for projectPath: String) -> Binding<Bool> {
        Binding(
            get: { selectedProjectPaths.contains(projectPath) },
            set: { isSelected in
                if isSelected {
                    selectedProjectPaths.insert(projectPath)
                } else {
                    selectedProjectPaths.remove(projectPath)
                }
            }
        )
    }

    private func projectName(for path: String) -> String {
        availableProjects.first(where: { $0.path == path })?.name ?? URL(fileURLWithPath: path).lastPathComponent
    }

    private func projectToggleLabel(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(project.name)
                .foregroundStyle(NativeTheme.textPrimary)
                .lineLimit(1)
            Text(project.path)
                .font(.caption2)
                .foregroundStyle(NativeTheme.textSecondary.opacity(0.8))
                .lineLimit(1)
            if !project.tags.isEmpty {
                Text(project.tags.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(NativeTheme.textSecondary.opacity(0.8))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(NativeTheme.textSecondary)
    }

    private func helperText(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(NativeTheme.textSecondary.opacity(0.85))
    }
}

struct WorkspaceAlignmentAddProjectsSheet: View {
    let workspaceName: String
    let availableProjects: [Project]
    let initiallySelectedPaths: Set<String>
    let onSubmit: (_ selectedPaths: Set<String>, _ applyRules: Bool) -> Void
    let onClose: () -> Void

    @State private var selectedPaths: Set<String>
    @State private var applyRulesAfterAdd: Bool = true
    @State private var projectSearchQuery = ""

    init(
        workspaceName: String,
        availableProjects: [Project],
        initiallySelectedPaths: Set<String> = [],
        onSubmit: @escaping (_ selectedPaths: Set<String>, _ applyRules: Bool) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.workspaceName = workspaceName
        self.availableProjects = availableProjects
        self.initiallySelectedPaths = initiallySelectedPaths
        self.onSubmit = onSubmit
        self.onClose = onClose
        _selectedPaths = State(initialValue: initiallySelectedPaths)
    }

    private var sortedProjects: [Project] {
        availableProjects.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var filteredProjects: [Project] {
        filterWorkspaceAlignmentProjects(sortedProjects, query: projectSearchQuery)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("添加项目到「\(workspaceName)」")
                .font(.headline)
                .foregroundStyle(NativeTheme.textPrimary)

            if sortedProjects.isEmpty {
                Text("没有可添加的项目。")
                    .font(.caption)
                    .foregroundStyle(NativeTheme.textSecondary)
            } else if filteredProjects.isEmpty {
                workspaceAlignmentSearchField(text: $projectSearchQuery)
                Text("没有匹配的项目。")
                    .font(.caption)
                    .foregroundStyle(NativeTheme.textSecondary)
            } else {
                workspaceAlignmentSearchField(text: $projectSearchQuery)
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(filteredProjects) { project in
                            Toggle(isOn: binding(for: project.path)) {
                                projectToggleLabel(project)
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                }
                .frame(minHeight: 160, maxHeight: 220)
            }

            Toggle("添加后立即应用工作区规则", isOn: $applyRulesAfterAdd)
                .toggleStyle(.checkbox)

            Spacer(minLength: 0)

            HStack {
                Spacer(minLength: 0)
                Button("取消", action: onClose)
                Button("添加") {
                    onSubmit(selectedPaths, applyRulesAfterAdd)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedPaths.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460, height: 420)
        .background(NativeTheme.window)
    }

    private func binding(for projectPath: String) -> Binding<Bool> {
        Binding(
            get: { selectedPaths.contains(projectPath) },
            set: { isSelected in
                if isSelected {
                    selectedPaths.insert(projectPath)
                } else {
                    selectedPaths.remove(projectPath)
                }
            }
        )
    }

    private func projectToggleLabel(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(project.name)
                .foregroundStyle(NativeTheme.textPrimary)
                .lineLimit(1)
            Text(project.path)
                .font(.caption2)
                .foregroundStyle(NativeTheme.textSecondary.opacity(0.8))
                .lineLimit(1)
            if !project.tags.isEmpty {
                Text(project.tags.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(NativeTheme.textSecondary.opacity(0.8))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func initialValueOrEmpty(_ value: String) -> String {
    value
}

private func filterWorkspaceAlignmentProjects(_ projects: [Project], query: String) -> [Project] {
    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedQuery.isEmpty else {
        return projects
    }
    let normalizedQuery = trimmedQuery.lowercased()
    return projects.filter { project in
        project.name.lowercased().contains(normalizedQuery)
            || project.path.lowercased().contains(normalizedQuery)
            || project.tags.contains(where: { $0.lowercased().contains(normalizedQuery) })
    }
}

private func workspaceAlignmentSearchField(text: Binding<String>) -> some View {
    HStack(spacing: 8) {
        Image(systemName: "magnifyingglass")
            .foregroundStyle(NativeTheme.textSecondary)
        TextField("搜索项目名称、路径或标签…", text: text)
            .textFieldStyle(.plain)
            .foregroundStyle(NativeTheme.textPrimary)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 9)
    .background(NativeTheme.elevated)
    .clipShape(.rect(cornerRadius: 10))
}
