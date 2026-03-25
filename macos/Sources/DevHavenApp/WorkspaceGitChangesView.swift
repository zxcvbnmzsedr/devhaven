import SwiftUI
import DevHavenCore

struct WorkspaceGitChangesView: View {
    @Bindable var viewModel: WorkspaceGitViewModel
    @State private var commitMessage = ""
    @State private var amend = false
    @State private var pendingDiscardPaths: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            actionBar
            commitBar
            if let mutationErrorMessage = viewModel.mutationErrorMessage {
                errorBanner(message: mutationErrorMessage)
                    .padding(.horizontal, 16)
            }

            if let snapshot = viewModel.workingTreeSnapshot {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        changesSection(title: "已暂存", items: snapshot.staged, trailingActionTitle: "取消暂存") { item in
                            viewModel.unstage(paths: [item.path])
                        }
                        changesSection(title: "未暂存", items: snapshot.unstaged, trailingActionTitle: "暂存") { item in
                            viewModel.stage(paths: [item.path])
                        }
                        changesSection(title: "未跟踪", items: snapshot.untracked, trailingActionTitle: "暂存") { item in
                            viewModel.stage(paths: [item.path])
                        }
                    }
                    .padding(16)
                }
            } else if viewModel.isLoading {
                ProgressView("正在加载变更…")
                    .tint(NativeTheme.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "暂无变更",
                    systemImage: "checkmark.circle",
                    description: Text("当前工作树没有已暂存、未暂存或未跟踪变更。")
                )
                .foregroundStyle(NativeTheme.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(NativeTheme.window)
        .confirmationDialog(
            "确认丢弃变更",
            isPresented: Binding(
                get: { !pendingDiscardPaths.isEmpty },
                set: { if !$0 { pendingDiscardPaths = [] } }
            ),
            titleVisibility: .visible
        ) {
            Button("丢弃", role: .destructive) {
                let paths = pendingDiscardPaths
                pendingDiscardPaths = []
                viewModel.discard(paths: paths)
            }
            Button("取消", role: .cancel) {
                pendingDiscardPaths = []
            }
        } message: {
            Text("将丢弃以下路径的本地改动：\(pendingDiscardPaths.joined(separator: ", "))")
        }
        .onChange(of: viewModel.successfulMutationToken) { _, _ in
            switch viewModel.lastSuccessfulMutation {
            case .commit, .amend:
                commitMessage = ""
            default:
                break
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button("全部暂存") {
                viewModel.stageAll()
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isMutating)

            Button("全部取消暂存") {
                viewModel.unstageAll()
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isMutating)

            Spacer(minLength: 8)

            if viewModel.isMutating {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private var commitBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("修订上一次提交", isOn: $amend)
                .toggleStyle(.checkbox)
                .foregroundStyle(NativeTheme.textPrimary)

            HStack(spacing: 8) {
                TextField(amend ? "修订提交信息（留空将 no-edit）" : "输入提交信息", text: $commitMessage)
                    .textFieldStyle(.roundedBorder)

                Button(amend ? "修订提交" : "提交") {
                    if amend {
                        let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
                        viewModel.amend(message: message.isEmpty ? nil : message)
                    } else {
                        viewModel.commit(message: commitMessage)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isMutating || (!amend && commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
        }
        .padding(.horizontal, 16)
    }

    private func changesSection(
        title: String,
        items: [WorkspaceGitFileStatus],
        trailingActionTitle: String,
        onTrailingAction: @escaping (WorkspaceGitFileStatus) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(NativeTheme.textPrimary)
                Spacer(minLength: 8)
                Text("\(items.count)")
                    .font(.caption)
                    .foregroundStyle(NativeTheme.textSecondary)
            }

            if items.isEmpty {
                Text("暂无条目")
                    .font(.caption)
                    .foregroundStyle(NativeTheme.textSecondary)
            } else {
                ForEach(items) { item in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.path)
                                .font(.callout.monospaced())
                                .foregroundStyle(NativeTheme.textPrimary)
                            if let originalPath = item.originalPath {
                                Text("来自 \(originalPath)")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(NativeTheme.textSecondary)
                            }
                        }

                        Spacer(minLength: 8)

                        Button(trailingActionTitle) {
                            onTrailingAction(item)
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.isMutating)

                        Button("丢弃", role: .destructive) {
                            pendingDiscardPaths = [item.path]
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.isMutating)
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
