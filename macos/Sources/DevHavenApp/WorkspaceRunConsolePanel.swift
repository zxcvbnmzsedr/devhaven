import SwiftUI
import DevHavenCore

struct WorkspaceRunConsolePanel: View {
    let consoleState: WorkspaceRunConsoleState
    let height: CGFloat
    let onSelectSession: (String) -> Void
    let onClear: () -> Void
    let onOpenLog: () -> Void
    let onHide: () -> Void
    @State private var isPinnedToBottom = true
    @State private var scrollViewportMaxY: CGFloat = .zero
    @State private var scrollBottomMarkerMaxY: CGFloat = .zero

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            logBody
            Divider()
            footer
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
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
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: WorkspaceRunConsoleBottomMarkerMaxYPreferenceKey.self,
                                    value: geometry.frame(in: .global).maxY
                                )
                            }
                        }
                }
                .padding(12)
            }
            .background(NativeTheme.window)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: WorkspaceRunConsoleViewportMaxYPreferenceKey.self,
                        value: geometry.frame(in: .global).maxY
                    )
                }
            }
            .onPreferenceChange(WorkspaceRunConsoleViewportMaxYPreferenceKey.self) { value in
                scrollViewportMaxY = value
                refreshPinnedToBottomState()
            }
            .onPreferenceChange(WorkspaceRunConsoleBottomMarkerMaxYPreferenceKey.self) { value in
                scrollBottomMarkerMaxY = value
                refreshPinnedToBottomState()
            }
            .onChange(of: consoleState.selectedSession?.id) { _, _ in
                isPinnedToBottom = true
                scrollToBottom(proxy)
            }
            .onChange(of: consoleState.selectedSession?.displayBuffer) { _, _ in
                guard isPinnedToBottom else { return }
                scrollToBottom(proxy)
            }
            .onAppear {
                scrollToBottom(proxy)
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

    private func refreshPinnedToBottomState() {
        let distance = scrollBottomMarkerMaxY - scrollViewportMaxY
        isPinnedToBottom = distance <= WorkspaceRunConsoleMetrics.autoScrollTolerance
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        proxy.scrollTo("workspace-run-console-bottom", anchor: .bottom)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private enum WorkspaceRunConsoleMetrics {
    static let autoScrollTolerance: CGFloat = 24
}

private struct WorkspaceRunConsoleViewportMaxYPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = .zero

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct WorkspaceRunConsoleBottomMarkerMaxYPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = .zero

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
