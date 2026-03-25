import SwiftUI
import DevHavenCore

struct WorkspaceGitOperationsView: View {
    @Bindable var viewModel: WorkspaceGitViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                worktreeCard
                if let mutationErrorMessage = viewModel.mutationErrorMessage {
                    errorBanner(message: mutationErrorMessage)
                }
                actionCard
                trackingCard
                remotesCard
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(NativeTheme.window)
    }

    private var worktreeCard: some View {
        card(title: "当前执行工作树") {
            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.selectedExecutionWorktree?.displayName ?? "未选择")
                    .font(.headline)
                    .foregroundStyle(NativeTheme.textPrimary)
                Text(viewModel.selectedExecutionWorktree?.path ?? viewModel.selectedExecutionWorktreePath)
                    .font(.caption.monospaced())
                    .foregroundStyle(NativeTheme.textSecondary)
                    .textSelection(.enabled)
            }
        }
    }

    private var actionCard: some View {
        card(title: "远端同步") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Button("抓取") {
                        viewModel.fetch()
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isMutating)

                    Button("拉取") {
                        viewModel.pull()
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isMutating)

                    Button("推送") {
                        viewModel.push()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isMutating)

                    Button("终止当前操作", role: .destructive) {
                        viewModel.abortOperation()
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isMutating || viewModel.operationState == .idle)
                }

                if viewModel.isMutatingOperations {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(currentMutationDescription)
                            .font(.caption)
                            .foregroundStyle(NativeTheme.textSecondary)
                    }
                }
            }
        }
    }

    private var trackingCard: some View {
        let aheadBehindSnapshot = viewModel.aheadBehindSnapshot
        let operationState = viewModel.operationState

        return card(title: "跟踪状态") {
            VStack(alignment: .leading, spacing: 10) {
                detailRow(title: "上游分支", value: aheadBehindSnapshot.upstream ?? "未配置")
                detailRow(title: "领先 / 落后", value: "\(aheadBehindSnapshot.ahead) / \(aheadBehindSnapshot.behind)")
                detailRow(title: "仓库状态", value: operationStateDescription(operationState))
            }
        }
    }

    private var remotesCard: some View {
        let remotes = viewModel.remotes

        return card(title: "远端列表") {
            if remotes.isEmpty {
                Text("当前仓库未配置远端。")
                    .font(.caption)
                    .foregroundStyle(NativeTheme.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(remotes) { remote in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(remote.name)
                                .font(.headline)
                                .foregroundStyle(NativeTheme.textPrimary)
                            Text("拉取地址：\(remote.fetchURL ?? "未配置")")
                                .font(.caption.monospaced())
                                .foregroundStyle(NativeTheme.textSecondary)
                                .textSelection(.enabled)
                            Text("推送地址：\(remote.pushURL ?? "未配置")")
                                .font(.caption.monospaced())
                                .foregroundStyle(NativeTheme.textSecondary)
                                .textSelection(.enabled)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(NativeTheme.elevated)
                        .clipShape(.rect(cornerRadius: 10))
                    }
                }
            }
        }
    }

    private var currentMutationDescription: String {
        switch viewModel.activeMutation {
        case .fetch:
            return "正在抓取远端最新引用…"
        case .pull:
            return "正在拉取当前 worktree 的最新提交…"
        case .push:
            return "正在推送当前 worktree 的本地提交…"
        case .abortOperation:
            return "正在终止当前 Git 操作…"
        default:
            return "正在执行 Git 操作…"
        }
    }

    private func operationStateDescription(_ state: WorkspaceGitOperationState) -> String {
        switch state {
        case .idle:
            return "空闲"
        case .merging:
            return "合并中"
        case .rebasing:
            return "变基中"
        case .cherryPicking:
            return "Cherry-pick 中"
        }
    }

    private func detailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(NativeTheme.textSecondary)
            Text(value)
                .font(.callout.monospaced())
                .foregroundStyle(NativeTheme.textPrimary)
                .textSelection(.enabled)
        }
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

    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(NativeTheme.textPrimary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(NativeTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(NativeTheme.border, lineWidth: 1)
        )
        .clipShape(.rect(cornerRadius: 14))
    }
}
