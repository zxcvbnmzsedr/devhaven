import SwiftUI
import DevHavenCore

struct WorkspaceRunConsolePanel: View {
    let consoleState: WorkspaceRunConsoleState
    let onSelectSession: (String) -> Void
    let onClear: () -> Void
    let onOpenLog: () -> Void
    let onHide: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            logBody
            Divider()
            footer
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .background(NativeTheme.panel)
    }

    private var header: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(consoleState.sessions) { session in
                        Button {
                            onSelectSession(session.id)
                        } label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(sessionColor(session.state))
                                    .frame(width: 6, height: 6)
                                Text(session.configurationName)
                                    .lineLimit(1)
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(consoleState.selectedSession?.id == session.id ? NativeTheme.textPrimary : NativeTheme.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(consoleState.selectedSession?.id == session.id ? NativeTheme.elevated : NativeTheme.surface)
                            .clipShape(.rect(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }

            Spacer(minLength: 0)

            Button("清空显示") {
                onClear()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(NativeTheme.textSecondary)

            Button("打开日志") {
                onOpenLog()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(NativeTheme.textSecondary)
            .disabled(consoleState.selectedSession?.logFilePath == nil)

            Button("收起") {
                onHide()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(NativeTheme.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var logBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(consoleState.selectedSession?.displayBuffer.nilIfEmpty ?? "暂无日志输出")
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(NativeTheme.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear
                        .frame(height: 1)
                        .id("workspace-run-console-bottom")
                }
                .padding(12)
            }
            .background(NativeTheme.window)
            .onChange(of: consoleState.selectedSession?.displayBuffer) { _, _ in
                proxy.scrollTo("workspace-run-console-bottom", anchor: .bottom)
            }
            .onAppear {
                proxy.scrollTo("workspace-run-console-bottom", anchor: .bottom)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text(consoleState.selectedSession.map(statusText(for:)) ?? "未选择运行配置")
                .font(.caption)
                .foregroundStyle(NativeTheme.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func sessionColor(_ state: WorkspaceRunSessionState) -> Color {
        switch state {
        case .starting, .stopping:
            return NativeTheme.warning
        case .running:
            return NativeTheme.accent
        case .stopped:
            return NativeTheme.textSecondary
        case .completed:
            return .green
        case .failed:
            return NativeTheme.danger
        }
    }

    private func statusText(for session: WorkspaceRunSession) -> String {
        let status: String = switch session.state {
        case .starting:
            "启动中"
        case .running:
            "运行中"
        case .stopping:
            "停止中"
        case .stopped:
            "已停止"
        case let .completed(exitCode):
            "已完成（退出码 \(exitCode)）"
        case let .failed(exitCode):
            "失败（退出码 \(exitCode)）"
        }
        return "\(session.configurationName) · \(status)"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
