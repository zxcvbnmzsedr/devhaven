import SwiftUI
import DevHavenCore

private enum WorkspaceWorktreeDialogMode: String, CaseIterable, Identifiable {
    case create = "创建"
    case openExisting = "打开已有"

    var id: String { rawValue }
}

private enum WorkspaceWorktreeBranchMode: String, CaseIterable, Identifiable {
    case existing = "已有分支"
    case new = "新建分支"

    var id: String { rawValue }
}

struct WorkspaceWorktreeDialogView: View {
    let sourceProject: Project
    let loadBranches: (String) async throws -> [NativeGitBranch]
    let loadWorktrees: (String) async throws -> [NativeGitWorktree]
    let managedPathPreview: (String, String) throws -> String
    let onCreateWorktree: (_ branch: String, _ createBranch: Bool, _ baseBranch: String?, _ autoOpen: Bool) async throws -> Void
    let onAddExistingWorktree: (_ worktreePath: String, _ branch: String, _ autoOpen: Bool) async throws -> Void
    let onClose: () -> Void

    @State private var mode: WorkspaceWorktreeDialogMode = .create
    @State private var branchMode: WorkspaceWorktreeBranchMode = .new
    @State private var branches = [NativeGitBranch]()
    @State private var existingWorktrees = [NativeGitWorktree]()
    @State private var existingBranch = ""
    @State private var newBranch = ""
    @State private var baseBranch = ""
    @State private var selectedExistingWorktreePath = ""
    @State private var autoOpen = true
    @State private var isLoadingBranches = false
    @State private var isLoadingWorktrees = false
    @State private var isSubmitting = false
    @State private var localError: String?

    private var activeBranch: String {
        branchMode == .existing ? existingBranch.trimmingCharacters(in: .whitespacesAndNewlines) : newBranch.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedExistingWorktree: NativeGitWorktree? {
        existingWorktrees.first(where: { $0.path == selectedExistingWorktreePath })
    }

    private var targetPathPreviewText: String {
        guard !activeBranch.isEmpty else {
            return "~/.devhaven/worktrees/<project>/<branch>"
        }
        return (try? managedPathPreview(sourceProject.path, activeBranch)) ?? "~/.devhaven/worktrees/<project>/<branch>"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            footer
        }
        .frame(minWidth: 540, minHeight: 620)
        .background(NativeTheme.window)
        .task {
            await reloadData()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("管理 worktree")
                    .font(.headline)
                    .foregroundStyle(NativeTheme.textPrimary)
                Text(sourceProject.name)
                    .font(.caption)
                    .foregroundStyle(NativeTheme.textSecondary)
            }
            Spacer(minLength: 0)
            Button("关闭", action: onClose)
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(NativeTheme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(NativeTheme.surface)
                .clipShape(.rect(cornerRadius: 8))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(NativeTheme.surface)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker("模式", selection: $mode) {
                    ForEach(WorkspaceWorktreeDialogMode.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                if mode == .create {
                    createContent
                } else {
                    existingContent
                }

                Toggle(isOn: $autoOpen) {
                    Text("完成后自动打开到右侧终端")
                        .font(.callout)
                        .foregroundStyle(NativeTheme.textPrimary)
                }
                .toggleStyle(.switch)

                if let localError, !localError.isEmpty {
                    Text(localError)
                        .font(.caption)
                        .foregroundStyle(NativeTheme.danger)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(NativeTheme.danger.opacity(0.12))
                        .clipShape(.rect(cornerRadius: 10))
                }
            }
            .padding(16)
        }
    }

    private var createContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("分支来源", selection: $branchMode) {
                ForEach(WorkspaceWorktreeBranchMode.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)

            if branchMode == .existing {
                fieldCard(title: "选择已有分支") {
                    if isLoadingBranches {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Picker("已有分支", selection: $existingBranch) {
                            ForEach(branches) { branch in
                                Text(branch.isMain ? "\(branch.name)（主分支）" : branch.name).tag(branch.name)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                }
            } else {
                fieldCard(title: "新分支名") {
                    TextField("例如 feature/worktree", text: $newBranch)
                        .textFieldStyle(.roundedBorder)
                }

                fieldCard(title: "基线分支") {
                    if isLoadingBranches {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Picker("基线分支", selection: $baseBranch) {
                            ForEach(branches) { branch in
                                Text(branch.isMain ? "\(branch.name)（主分支）" : branch.name).tag(branch.name)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                }
            }

            fieldCard(title: "目标路径预览") {
                Text(targetPathPreviewText)
                    .font(.caption.monospaced())
                    .foregroundStyle(NativeTheme.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var existingContent: some View {
        fieldCard(title: "选择已有 worktree") {
            if isLoadingWorktrees {
                ProgressView()
                    .controlSize(.small)
            } else if existingWorktrees.isEmpty {
                Text("当前仓库没有可添加的已有 worktree。")
                    .font(.caption)
                    .foregroundStyle(NativeTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Picker("已有 worktree", selection: $selectedExistingWorktreePath) {
                    ForEach(existingWorktrees) { item in
                        Text("\(item.branch) · \(item.path)").tag(item.path)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            Button("取消", action: onClose)
                .buttonStyle(.plain)
                .foregroundStyle(NativeTheme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(NativeTheme.surface)
                .clipShape(.rect(cornerRadius: 8))

            Button(actionButtonTitle) {
                Task {
                    await submit()
                }
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting || !canSubmit)
            .foregroundStyle(Color.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(canSubmit ? NativeTheme.accent : NativeTheme.accent.opacity(0.4))
            .clipShape(.rect(cornerRadius: 8))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(NativeTheme.surface)
    }

    private var canSubmit: Bool {
        if mode == .openExisting {
            return selectedExistingWorktree != nil
        }
        if branchMode == .existing {
            return !existingBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return !newBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !baseBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var actionButtonTitle: String {
        if isSubmitting {
            return "处理中..."
        }
        return mode == .create ? "创建" : "添加并打开"
    }

    private func fieldCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(NativeTheme.textSecondary)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NativeTheme.elevated)
        .clipShape(.rect(cornerRadius: 12))
    }

    private func reloadData() async {
        localError = nil
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await loadBranchList()
            }
            group.addTask {
                await loadExistingWorktrees()
            }
        }
    }

    @MainActor
    private func submit() async {
        guard !isSubmitting else {
            return
        }
        localError = nil
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            if mode == .create {
                let branch = activeBranch
                if branchMode == .existing && branch.isEmpty {
                    localError = "分支名不能为空"
                    return
                }
                if branchMode == .new && baseBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    localError = "基线分支不能为空"
                    return
                }
                try await onCreateWorktree(
                    branch,
                    branchMode == .new,
                    branchMode == .new ? baseBranch : nil,
                    autoOpen
                )
                onClose()
            } else {
                guard let existing = selectedExistingWorktree else {
                    localError = "请选择已有 worktree"
                    return
                }
                try await onAddExistingWorktree(existing.path, existing.branch, autoOpen)
                onClose()
            }
        } catch {
            localError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    @MainActor
    private func loadBranchList() async {
        isLoadingBranches = true
        defer { isLoadingBranches = false }
        do {
            let items = try await loadBranches(sourceProject.path)
            branches = items
            existingBranch = items.first(where: \.isMain)?.name ?? items.first?.name ?? ""
            baseBranch = items.first(where: { $0.name == "develop" })?.name ?? existingBranch
        } catch {
            localError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    @MainActor
    private func loadExistingWorktrees() async {
        isLoadingWorktrees = true
        defer { isLoadingWorktrees = false }
        do {
            let items = try await loadWorktrees(sourceProject.path)
            existingWorktrees = items
            selectedExistingWorktreePath = items.first?.path ?? ""
        } catch {
            localError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
