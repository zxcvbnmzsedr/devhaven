import SwiftUI
import DevHavenCore

struct WorkspacePlaceholderView: View {
    let project: Project?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Workspace 子系统预留区", systemImage: "terminal")
                .font(.title3.weight(.semibold))

            if let project {
                Text("当前项目：\(project.name)")
                    .font(.headline)
                Text(project.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                Text("当前未选择项目")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("本轮已切到原生主壳，但终端工作区不在首批覆盖范围。")
                Text("这里保留为后续 Ghostty / pane / tab / split 原生子系统的接入位。")
                Text("当前阶段请优先使用中间栏完成项目浏览、备注、Todo、设置、回收站与自动化配置查看。")
            }
            .font(.body)
            .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}
