import SwiftUI
import DevHavenCore

struct WorkspaceRunToolbarView: View {
    let configurations: [WorkspaceRunConfiguration]
    let selectedConfigurationID: String?
    let canRun: Bool
    let canStop: Bool
    let hasSessions: Bool
    let isLogsVisible: Bool
    let onSelectConfiguration: (String) -> Void
    let onRun: () -> Void
    let onStop: () -> Void
    let onToggleLogs: () -> Void
    let onConfigure: () -> Void

    private var selectedConfigurationName: String {
        configurations.first(where: { $0.id == selectedConfigurationID })?.name
            ?? configurations.first?.name
            ?? "无配置"
    }

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                if configurations.isEmpty {
                    Text("当前项目暂无可运行配置")
                } else {
                    ForEach(configurations) { configuration in
                        Button(configuration.name) {
                            onSelectConfiguration(configuration.id)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.down.circle")
                    Text(selectedConfigurationName)
                        .lineLimit(1)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(configurations.isEmpty ? NativeTheme.textSecondary : NativeTheme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(NativeTheme.surface)
                .clipShape(.rect(cornerRadius: 8))
            }
            .menuStyle(.borderlessButton)

            Button("Run") {
                onRun()
            }
            .buttonStyle(.borderedProminent)
            .tint(NativeTheme.accent)
            .disabled(!canRun)

            Button("Stop") {
                onStop()
            }
            .buttonStyle(.bordered)
            .disabled(!canStop)

            Button("Logs") {
                onToggleLogs()
            }
            .buttonStyle(.bordered)
            .disabled(!hasSessions)
            .opacity(isLogsVisible ? 1 : 0.9)

            Button("配置") {
                onConfigure()
            }
            .buttonStyle(.bordered)
        }
    }
}
