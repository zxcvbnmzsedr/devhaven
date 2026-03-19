import SwiftUI
import DevHavenCore

struct WorkspaceHostView: View {
    let project: Project
    let launchRequest: WorkspaceTerminalLaunchRequest
    let onOpenInTerminal: () -> Void
    let onBack: () -> Void
    let onShowDetails: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            WorkspaceTerminalPaneView(
                request: launchRequest
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(20)
        .background(NativeTheme.window)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(project.name)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(NativeTheme.textPrimary)
                    Text(project.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(NativeTheme.textSecondary)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 0)
                Button("返回项目列表", action: onBack)
                    .buttonStyle(.borderless)
                    .foregroundStyle(NativeTheme.textSecondary)
            }

            HStack(spacing: 12) {
                actionButton(
                    title: "外部 Terminal",
                    systemImage: "arrow.up.right.square",
                    action: onOpenInTerminal
                )
                actionButton(
                    title: "查看详情",
                    systemImage: "sidebar.right",
                    action: onShowDetails
                )
                statChip(
                    title: "\(project.gitCommits) 次提交",
                    systemImage: "point.3.connected.trianglepath.dotted"
                )
                statChip(
                    title: launchRequest.terminalRuntime,
                    systemImage: "terminal"
                )
                Spacer(minLength: 0)
            }
        }
    }

    private func actionButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.callout.weight(.semibold))
                .foregroundStyle(NativeTheme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(NativeTheme.elevated)
                .clipShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func statChip(title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(.caption)
        .foregroundStyle(NativeTheme.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(NativeTheme.surface)
        .clipShape(.rect(cornerRadius: 10))
    }
}
