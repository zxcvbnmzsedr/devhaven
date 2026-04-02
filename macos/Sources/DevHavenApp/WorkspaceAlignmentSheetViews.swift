import SwiftUI
import DevHavenCore

struct WorkspaceAlignmentEditorFormData: Equatable {
    var name: String
    var members: [WorkspaceAlignmentMemberFormEntry]
    var applyRulesAfterSave: Bool
}

struct WorkspaceAlignmentMemberFormEntry: Equatable, Identifiable {
    var projectPath: String
    var alias: String
    var targetBranch: String
    var baseBranchMode: WorkspaceAlignmentBaseBranchMode
    var specifiedBaseBranch: String

    var id: String { projectPath }
}

enum WorkspaceAlignmentEditorSheetMode: Equatable {
    case create
    case edit
}

struct WorkspaceAlignmentEditorSheet: View {
    let title: String
    let mode: WorkspaceAlignmentEditorSheetMode
    let availableProjects: [Project]
    let loadBaseBranchReferences: (String) async throws -> [NativeGitBaseBranchReference]
    let initialData: WorkspaceAlignmentEditorFormData
    let errorMessage: String?
    let isSubmitting: Bool
    let onSubmit: (WorkspaceAlignmentEditorFormData) -> Void
    let onClose: () -> Void

    @State private var name: String
    @State private var selectedProjectPaths: Set<String>
    @State private var memberEntriesByPath: [String: WorkspaceAlignmentMemberFormEntry]
    @State private var applyRulesAfterSave: Bool
    @State private var projectSearchQuery = ""

    init(
        title: String,
        mode: WorkspaceAlignmentEditorSheetMode,
        availableProjects: [Project],
        loadBaseBranchReferences: @escaping (String) async throws -> [NativeGitBaseBranchReference],
        initialData: WorkspaceAlignmentEditorFormData,
        errorMessage: String? = nil,
        isSubmitting: Bool = false,
        onSubmit: @escaping (WorkspaceAlignmentEditorFormData) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.title = title
        self.mode = mode
        self.availableProjects = availableProjects
        self.loadBaseBranchReferences = loadBaseBranchReferences
        self.initialData = initialData
        self.errorMessage = errorMessage
        self.isSubmitting = isSubmitting
        self.onSubmit = onSubmit
        self.onClose = onClose
        _name = State(initialValue: initialData.name)
        _selectedProjectPaths = State(initialValue: Set(initialData.members.map(\.projectPath)))
        _memberEntriesByPath = State(
            initialValue: Dictionary(uniqueKeysWithValues: initialData.members.map { ($0.projectPath, $0) })
        )
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
        guard !trimmedName.isEmpty else {
            return false
        }
        for member in selectedMembers {
            if member.targetBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return false
            }
            if member.specifiedBaseBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return false
            }
        }
        return true
    }

    private var selectedMembers: [WorkspaceAlignmentMemberFormEntry] {
        selectedProjectPaths
            .compactMap { memberEntriesByPath[$0] }
            .sorted { lhs, rhs in
                projectName(for: lhs.projectPath).localizedStandardCompare(projectName(for: rhs.projectPath)) == .orderedAscending
            }
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
                    .disabled(isSubmitting)
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
                            .disabled(isSubmitting)
                        helperText("没有匹配的项目，换个关键词试试。")
                    } else {
                        workspaceAlignmentSearchField(text: $projectSearchQuery)
                            .disabled(isSubmitting)
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(filteredProjects) { project in
                                    Toggle(isOn: selectionBinding(for: project.path)) {
                                        projectToggleLabel(project)
                                    }
                                    .toggleStyle(.checkbox)
                                    .disabled(isSubmitting)
                                }
                            }
                        }
                        .frame(minHeight: 120, maxHeight: 160)
                    }
                }
            case .edit:
                EmptyView()
            }

            VStack(alignment: .leading, spacing: 10) {
                fieldLabel("成员配置")
                if selectedMembers.isEmpty {
                    helperText("当前没有成员。可先创建空工作区，后续再添加项目。")
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(selectedMembers) { member in
                                WorkspaceAlignmentMemberEditorCard(
                                    title: projectName(for: member.projectPath),
                                    subtitle: member.projectPath,
                                    projectPath: member.projectPath,
                                    entry: binding(for: member.projectPath),
                                    loadBaseBranchReferences: loadBaseBranchReferences,
                                    isSubmitting: isSubmitting
                                )
                            }
                        }
                    }
                    .frame(minHeight: 180, maxHeight: mode == .create ? 260 : 320)
                }
            }

            Toggle("保存后立即应用工作区规则", isOn: $applyRulesAfterSave)
                .toggleStyle(.checkbox)
                .disabled(isSubmitting)

            if let errorMessage = normalizedErrorMessage {
                submissionErrorText(errorMessage)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer(minLength: 0)
                Button("取消", action: onClose)
                    .disabled(isSubmitting)
                Button {
                    onSubmit(
                        WorkspaceAlignmentEditorFormData(
                            name: name,
                            members: selectedMembers,
                            applyRulesAfterSave: applyRulesAfterSave
                        )
                    )
                } label: {
                    submitButtonLabel(primaryButtonTitle)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit || isSubmitting)
            }
        }
        .padding(20)
        .frame(width: 540, height: mode == .create ? 720 : 620)
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

    private var normalizedErrorMessage: String? {
        let trimmed = errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }

    private func selectionBinding(for projectPath: String) -> Binding<Bool> {
        Binding(
            get: { selectedProjectPaths.contains(projectPath) },
            set: { isSelected in
                if isSelected {
                    selectedProjectPaths.insert(projectPath)
                    if memberEntriesByPath[projectPath] == nil {
                        memberEntriesByPath[projectPath] = makeDefaultMemberEntry(for: projectPath)
                    }
                } else {
                    selectedProjectPaths.remove(projectPath)
                }
            }
        )
    }

    private func binding(for projectPath: String) -> Binding<WorkspaceAlignmentMemberFormEntry> {
        Binding(
            get: { memberEntriesByPath[projectPath] ?? makeDefaultMemberEntry(for: projectPath) },
            set: { updatedValue in
                memberEntriesByPath[projectPath] = updatedValue
            }
        )
    }

    private func projectName(for path: String) -> String {
        availableProjects.first(where: { $0.path == path })?.name ?? {
            let projectName = (path as NSString).lastPathComponent
            return projectName.isEmpty ? path : projectName
        }()
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

    private func makeDefaultMemberEntry(for projectPath: String) -> WorkspaceAlignmentMemberFormEntry {
        WorkspaceAlignmentMemberFormEntry(
            projectPath: projectPath,
            alias: sanitizeWorkspaceAlias(projectName(for: projectPath)),
            targetBranch: "",
            baseBranchMode: .specified,
            specifiedBaseBranch: ""
        )
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

    @ViewBuilder
    private func submissionErrorText(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(NativeTheme.danger)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(NativeTheme.danger.opacity(0.12))
            .clipShape(.rect(cornerRadius: 10))
    }

    @ViewBuilder
    private func submitButtonLabel(_ title: String) -> some View {
        HStack(spacing: 8) {
            if isSubmitting {
                ProgressView()
                    .controlSize(.small)
            }
            Text(isSubmitting ? "处理中…" : title)
        }
    }
}

struct WorkspaceAlignmentAddProjectsSheet: View {
    let workspaceName: String
    let availableProjects: [Project]
    let loadBaseBranchReferences: (String) async throws -> [NativeGitBaseBranchReference]
    let initialMemberTemplate: WorkspaceAlignmentMemberFormEntry?
    let initialSelectedProjectPaths: Set<String>
    let errorMessage: String?
    let isSubmitting: Bool
    let onSubmit: (_ members: [WorkspaceAlignmentMemberFormEntry], _ applyRules: Bool) -> Void
    let onClose: () -> Void

    @State private var selectedPaths: Set<String> = []
    @State private var memberEntriesByPath: [String: WorkspaceAlignmentMemberFormEntry]
    @State private var applyRulesAfterAdd: Bool = true
    @State private var projectSearchQuery = ""

    init(
        workspaceName: String,
        availableProjects: [Project],
        loadBaseBranchReferences: @escaping (String) async throws -> [NativeGitBaseBranchReference],
        initialMemberTemplate: WorkspaceAlignmentMemberFormEntry? = nil,
        initialSelectedProjectPaths: Set<String> = [],
        errorMessage: String? = nil,
        isSubmitting: Bool = false,
        onSubmit: @escaping (_ members: [WorkspaceAlignmentMemberFormEntry], _ applyRules: Bool) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.workspaceName = workspaceName
        self.availableProjects = availableProjects
        self.loadBaseBranchReferences = loadBaseBranchReferences
        self.initialMemberTemplate = initialMemberTemplate
        self.initialSelectedProjectPaths = initialSelectedProjectPaths
        self.errorMessage = errorMessage
        self.isSubmitting = isSubmitting
        self.onSubmit = onSubmit
        self.onClose = onClose
        let initialEntries = Dictionary(uniqueKeysWithValues: initialSelectedProjectPaths.map { path in
            let projectName = availableProjects.first(where: { $0.path == path })?.name ?? {
                let name = (path as NSString).lastPathComponent
                return name.isEmpty ? path : name
            }()
            return (
                path,
                WorkspaceAlignmentMemberFormEntry(
                    projectPath: path,
                    alias: sanitizeWorkspaceAlias(projectName),
                    targetBranch: initialMemberTemplate?.targetBranch ?? "",
                    baseBranchMode: .specified,
                    specifiedBaseBranch: initialMemberTemplate?.specifiedBaseBranch ?? ""
                )
            )
        })
        _selectedPaths = State(initialValue: initialSelectedProjectPaths)
        _memberEntriesByPath = State(initialValue: initialEntries)
    }

    private var sortedProjects: [Project] {
        availableProjects.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var filteredProjects: [Project] {
        filterWorkspaceAlignmentProjects(sortedProjects, query: projectSearchQuery)
    }

    private var selectedMembers: [WorkspaceAlignmentMemberFormEntry] {
        selectedPaths
            .compactMap { memberEntriesByPath[$0] }
            .sorted { lhs, rhs in
                projectName(for: lhs.projectPath).localizedStandardCompare(projectName(for: rhs.projectPath)) == .orderedAscending
            }
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
                    .disabled(isSubmitting)
                Text("没有匹配的项目。")
                    .font(.caption)
                    .foregroundStyle(NativeTheme.textSecondary)
            } else {
                workspaceAlignmentSearchField(text: $projectSearchQuery)
                    .disabled(isSubmitting)
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(filteredProjects) { project in
                            Toggle(isOn: selectionBinding(for: project.path)) {
                                projectToggleLabel(project)
                            }
                            .toggleStyle(.checkbox)
                            .disabled(isSubmitting)
                        }
                    }
                }
                .frame(minHeight: 160, maxHeight: 220)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("新增成员配置")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NativeTheme.textSecondary)
                if selectedMembers.isEmpty {
                    Text("先选择要加入工作区的项目。")
                        .font(.caption)
                        .foregroundStyle(NativeTheme.textSecondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(selectedMembers) { member in
                                WorkspaceAlignmentMemberEditorCard(
                                    title: projectName(for: member.projectPath),
                                    subtitle: member.projectPath,
                                    projectPath: member.projectPath,
                                    entry: memberBinding(for: member.projectPath),
                                    loadBaseBranchReferences: loadBaseBranchReferences,
                                    isSubmitting: isSubmitting
                                )
                            }
                        }
                    }
                    .frame(minHeight: 140, maxHeight: 220)
                }
            }

            Toggle("添加后立即应用工作区规则", isOn: $applyRulesAfterAdd)
                .toggleStyle(.checkbox)
                .disabled(isSubmitting)

            if let errorMessage = normalizedErrorMessage {
                submissionErrorText(errorMessage)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer(minLength: 0)
                Button("取消", action: onClose)
                    .disabled(isSubmitting)
                Button {
                    onSubmit(selectedMembers, applyRulesAfterAdd)
                } label: {
                    submitButtonLabel("添加")
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedMembers.isEmpty || selectedMembers.contains(where: { member in
                    member.targetBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    member.specifiedBaseBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }) || isSubmitting)
            }
        }
        .padding(20)
        .frame(width: 540, height: 620)
        .background(NativeTheme.window)
    }

    private func selectionBinding(for projectPath: String) -> Binding<Bool> {
        Binding(
            get: { selectedPaths.contains(projectPath) },
            set: { isSelected in
                if isSelected {
                    selectedPaths.insert(projectPath)
                    if memberEntriesByPath[projectPath] == nil {
                        memberEntriesByPath[projectPath] = makeDefaultMemberEntry(for: projectPath)
                    }
                } else {
                    selectedPaths.remove(projectPath)
                }
            }
        )
    }

    private func memberBinding(for projectPath: String) -> Binding<WorkspaceAlignmentMemberFormEntry> {
        Binding(
            get: { memberEntriesByPath[projectPath] ?? makeDefaultMemberEntry(for: projectPath) },
            set: { memberEntriesByPath[projectPath] = $0 }
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

    private func projectName(for path: String) -> String {
        availableProjects.first(where: { $0.path == path })?.name ?? {
            let projectName = (path as NSString).lastPathComponent
            return projectName.isEmpty ? path : projectName
        }()
    }

    private func makeDefaultMemberEntry(for projectPath: String) -> WorkspaceAlignmentMemberFormEntry {
        WorkspaceAlignmentMemberFormEntry(
            projectPath: projectPath,
            alias: sanitizeWorkspaceAlias(projectName(for: projectPath)),
            targetBranch: initialMemberTemplate?.targetBranch ?? "",
            baseBranchMode: .specified,
            specifiedBaseBranch: initialMemberTemplate?.specifiedBaseBranch ?? ""
        )
    }

    private var normalizedErrorMessage: String? {
        let trimmed = errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }

    @ViewBuilder
    private func submissionErrorText(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(NativeTheme.danger)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(NativeTheme.danger.opacity(0.12))
            .clipShape(.rect(cornerRadius: 10))
    }

    @ViewBuilder
    private func submitButtonLabel(_ title: String) -> some View {
        HStack(spacing: 8) {
            if isSubmitting {
                ProgressView()
                    .controlSize(.small)
            }
            Text(isSubmitting ? "处理中…" : title)
        }
    }
}

private struct WorkspaceAlignmentMemberEditorCard: View {
    let title: String
    let subtitle: String
    let projectPath: String
    @Binding var entry: WorkspaceAlignmentMemberFormEntry
    let loadBaseBranchReferences: (String) async throws -> [NativeGitBaseBranchReference]
    let isSubmitting: Bool

    @State private var availableBaseBranchReferences = [NativeGitBaseBranchReference]()
    @State private var isLoadingBaseBranches = false
    @State private var baseBranchLoadErrorMessage: String?

    private var localBaseBranchReferences: [NativeGitBaseBranchReference] {
        availableBaseBranchReferences.filter { $0.kind == .local }
    }

    private var remoteBaseBranchReferences: [NativeGitBaseBranchReference] {
        availableBaseBranchReferences.filter { $0.kind == .remote }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(NativeTheme.textPrimary)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(NativeTheme.textSecondary.opacity(0.85))
                    .lineLimit(1)
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Alias")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NativeTheme.textSecondary)
                    TextField("例如：api", text: $entry.alias)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isSubmitting)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    Text("目标 branch")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NativeTheme.textSecondary)
                    TextField("例如：feature/payment", text: $entry.targetBranch)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isSubmitting)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("基线分支")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NativeTheme.textSecondary)
                if isLoadingBaseBranches {
                    ProgressView()
                        .controlSize(.small)
                } else if let baseBranchLoadErrorMessage, !baseBranchLoadErrorMessage.isEmpty {
                    Text(baseBranchLoadErrorMessage)
                        .font(.caption2)
                        .foregroundStyle(NativeTheme.danger)
                } else if availableBaseBranchReferences.isEmpty {
                    Text("当前仓库没有可选基线分支")
                        .font(.caption2)
                        .foregroundStyle(NativeTheme.textSecondary)
                } else {
                    Picker("基线分支", selection: $entry.specifiedBaseBranch) {
                        if !localBaseBranchReferences.isEmpty {
                            Section {
                                ForEach(localBaseBranchReferences) { branchReference in
                                    Text(workspaceAlignmentBaseBranchLabel(branchReference))
                                        .tag(branchReference.name)
                                }
                            } header: {
                                Text("本地")
                            }
                        }
                        if !remoteBaseBranchReferences.isEmpty {
                            Section {
                                ForEach(remoteBaseBranchReferences) { branchReference in
                                    Text(workspaceAlignmentBaseBranchLabel(branchReference))
                                        .tag(branchReference.name)
                                }
                            } header: {
                                Text("远端")
                            }
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .disabled(isSubmitting)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NativeTheme.elevated)
        .clipShape(.rect(cornerRadius: 10))
        .task(id: projectPath) {
            await loadAvailableBaseBranches()
        }
    }

    @MainActor
    private func loadAvailableBaseBranches() async {
        guard !projectPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            availableBaseBranchReferences = []
            baseBranchLoadErrorMessage = nil
            entry.baseBranchMode = .specified
            entry.specifiedBaseBranch = ""
            return
        }
        guard !isLoadingBaseBranches else {
            return
        }
        isLoadingBaseBranches = true
        baseBranchLoadErrorMessage = nil
        defer { isLoadingBaseBranches = false }

        do {
            let branchReferences = try await loadBaseBranchReferences(projectPath)
            availableBaseBranchReferences = branchReferences
            synchronizeBaseBranchSelection(with: branchReferences)
        } catch {
            availableBaseBranchReferences = []
            baseBranchLoadErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            entry.baseBranchMode = .specified
        }
    }

    @MainActor
    private func synchronizeBaseBranchSelection(with branchReferences: [NativeGitBaseBranchReference]) {
        entry.baseBranchMode = .specified
        let trimmedSelection = entry.specifiedBaseBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        if branchReferences.contains(where: { $0.name == trimmedSelection }) {
            if entry.specifiedBaseBranch != trimmedSelection {
                entry.specifiedBaseBranch = trimmedSelection
            }
            return
        }
        entry.specifiedBaseBranch = preferredWorkspaceAlignmentBaseBranch(from: branchReferences) ?? ""
    }
}

private func initialValueOrEmpty(_ value: String) -> String {
    value
}

private func preferredWorkspaceAlignmentBaseBranch(from branches: [NativeGitBaseBranchReference]) -> String? {
    branches.first(where: { $0.kind == .local && $0.isMain })?.name
        ?? branches.first(where: { $0.kind == .local })?.name
        ?? branches.first(where: { $0.kind == .remote && $0.isMain })?.name
        ?? branches.first?.name
}

private func workspaceAlignmentBaseBranchLabel(_ branchReference: NativeGitBaseBranchReference) -> String {
    if branchReference.isMain {
        return "\(branchReference.name)（主分支）"
    }
    return branchReference.name
}

func sanitizeWorkspaceAlias(_ rawValue: String) -> String {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let replaced = trimmed
        .replacingOccurrences(of: #"[^A-Za-z0-9._-]+"#, with: "-", options: .regularExpression)
        .trimmingCharacters(in: CharacterSet(charactersIn: "-._"))
    return replaced.isEmpty ? "member" : replaced
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
