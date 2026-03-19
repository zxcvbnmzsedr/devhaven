import SwiftUI
import DevHavenCore

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    private let originalSettings: AppSettings
    private let onCancel: () -> Void
    private let onSave: (AppSettings) -> Void

    @State private var terminalUseWebglRenderer: Bool
    @State private var terminalTheme: String
    @State private var sharedScriptsRoot: String
    @State private var viteDevPort: String
    @State private var webEnabled: Bool
    @State private var webBindHost: String
    @State private var webBindPort: String
    @State private var gitIdentities: [GitIdentity]

    init(settings: AppSettings, onCancel: @escaping () -> Void, onSave: @escaping (AppSettings) -> Void) {
        self.originalSettings = settings
        self.onCancel = onCancel
        self.onSave = onSave
        _terminalUseWebglRenderer = State(initialValue: settings.terminalUseWebglRenderer)
        _terminalTheme = State(initialValue: settings.terminalTheme)
        _sharedScriptsRoot = State(initialValue: settings.sharedScriptsRoot)
        _viteDevPort = State(initialValue: String(settings.viteDevPort))
        _webEnabled = State(initialValue: settings.webEnabled)
        _webBindHost = State(initialValue: settings.webBindHost)
        _webBindPort = State(initialValue: String(settings.webBindPort))
        _gitIdentities = State(initialValue: settings.gitIdentities)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("设置")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    onCancel()
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Form {
                Section("终端") {
                    Toggle("启用 WebGL 渲染", isOn: $terminalUseWebglRenderer)
                    TextField("终端主题", text: $terminalTheme)
                }

                Section("服务") {
                    TextField("共享脚本目录", text: $sharedScriptsRoot)
                    TextField("浏览器访问端口", text: $viteDevPort)
                    Toggle("启用 Web 服务", isOn: $webEnabled)
                    TextField("Web 绑定主机", text: $webBindHost)
                    TextField("Web 绑定端口", text: $webBindPort)
                }

                Section("Git 身份") {
                    ForEach(Array(gitIdentities.enumerated()), id: \.offset) { index, identity in
                        HStack {
                            TextField("姓名", text: Binding(
                                get: { gitIdentities[index].name },
                                set: { gitIdentities[index].name = $0 }
                            ))
                            TextField("邮箱", text: Binding(
                                get: { gitIdentities[index].email },
                                set: { gitIdentities[index].email = $0 }
                            ))
                            Button(role: .destructive) {
                                gitIdentities.remove(at: index)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    Button("新增身份") {
                        gitIdentities.append(GitIdentity(name: "", email: ""))
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("取消") {
                    onCancel()
                    dismiss()
                }
                Button("保存") {
                    onSave(buildSettings())
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
        .frame(minWidth: 720, minHeight: 560)
    }

    private func buildSettings() -> AppSettings {
        AppSettings(
            editorOpenTool: originalSettings.editorOpenTool,
            terminalOpenTool: originalSettings.terminalOpenTool,
            terminalUseWebglRenderer: terminalUseWebglRenderer,
            terminalTheme: terminalTheme.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? originalSettings.terminalTheme : terminalTheme,
            gitIdentities: gitIdentities.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !$0.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            projectListViewMode: originalSettings.projectListViewMode,
            sharedScriptsRoot: sharedScriptsRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? originalSettings.sharedScriptsRoot : sharedScriptsRoot,
            viteDevPort: Int(viteDevPort) ?? originalSettings.viteDevPort,
            webEnabled: webEnabled,
            webBindHost: webBindHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? originalSettings.webBindHost : webBindHost,
            webBindPort: Int(webBindPort) ?? originalSettings.webBindPort
        )
    }
}
