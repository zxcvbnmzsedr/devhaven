import SwiftUI
import DevHavenCore

struct WorkspaceGitBranchesView: View {
    @Bindable var viewModel: WorkspaceGitViewModel
    @State private var newBranchName = ""
    @State private var startPoint = ""
    @State private var pendingDeleteBranchName: String?

    private var localBranches: [WorkspaceGitBranchSnapshot] {
        viewModel.logSnapshot.refs.localBranches
    }

    private var remoteBranches: [WorkspaceGitBranchSnapshot] {
        viewModel.logSnapshot.refs.remoteBranches
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            createBranchCard
            if let mutationErrorMessage = viewModel.mutationErrorMessage {
                errorBanner(message: mutationErrorMessage)
                    .padding(.horizontal, 16)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    branchSection(title: "本地分支", branches: localBranches, isLocal: true)
                    branchSection(title: "远端分支", branches: remoteBranches, isLocal: false)
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(NativeTheme.window)
        .confirmationDialog(
            "删除本地分支",
            isPresented: Binding(
                get: { pendingDeleteBranchName != nil },
                set: { if !$0 { pendingDeleteBranchName = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                guard let pendingDeleteBranchName else {
                    return
                }
                let name = pendingDeleteBranchName
                self.pendingDeleteBranchName = nil
                viewModel.deleteLocalBranch(name: name)
            }
            Button("取消", role: .cancel) {
                pendingDeleteBranchName = nil
            }
        } message: {
            Text("将删除本地分支：\(pendingDeleteBranchName ?? "")")
        }
        .onChange(of: viewModel.successfulMutationToken) { _, _ in
            switch viewModel.lastSuccessfulMutation {
            case .createBranch:
                newBranchName = ""
                startPoint = ""
            default:
                break
            }
        }
    }

    private var createBranchCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("创建分支")
                .font(.headline)
                .foregroundStyle(NativeTheme.textPrimary)

            HStack(spacing: 8) {
                TextField("新分支名", text: $newBranchName)
                    .textFieldStyle(.roundedBorder)
                TextField("起点（可选）", text: $startPoint)
                    .textFieldStyle(.roundedBorder)
                Button("创建") {
                    let normalizedStartPoint = startPoint.trimmingCharacters(in: .whitespacesAndNewlines)
                    viewModel.createBranch(
                        name: newBranchName,
                        startPoint: normalizedStartPoint.isEmpty ? nil : normalizedStartPoint
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isMutating || newBranchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
    }

    private func branchSection(title: String, branches: [WorkspaceGitBranchSnapshot], isLocal: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(NativeTheme.textPrimary)
                Spacer(minLength: 8)
                Text("\(branches.count)")
                    .font(.caption)
                    .foregroundStyle(NativeTheme.textSecondary)
            }

            if branches.isEmpty {
                Text("暂无分支")
                    .font(.caption)
                    .foregroundStyle(NativeTheme.textSecondary)
            } else {
                ForEach(branches) { branch in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(branch.name)
                                .font(.callout.monospaced())
                                .foregroundStyle(NativeTheme.textPrimary)
                            if branch.isCurrent {
                                Text("当前分支")
                                    .font(.caption2)
                                    .foregroundStyle(NativeTheme.accent)
                            }
                        }

                        Spacer(minLength: 8)

                        if isLocal {
                            Button("切换到该分支") {
                                viewModel.checkoutBranch(name: branch.name)
                            }
                            .buttonStyle(.bordered)
                            .disabled(viewModel.isMutating || branch.isCurrent)

                            Button("删除分支", role: .destructive) {
                                pendingDeleteBranchName = branch.name
                            }
                            .buttonStyle(.bordered)
                            .disabled(viewModel.isMutating || branch.isCurrent)
                        }
                    }
                    .padding(10)
                    .background(NativeTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(NativeTheme.border, lineWidth: 1)
                    )
                    .clipShape(.rect(cornerRadius: 10))
                }
            }
        }
        .padding(14)
        .background(NativeTheme.elevated)
        .clipShape(.rect(cornerRadius: 12))
    }

    private func errorBanner(message: String) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(NativeTheme.warning)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NativeTheme.warning.opacity(0.12))
            .clipShape(.rect(cornerRadius: 12))
    }
}
