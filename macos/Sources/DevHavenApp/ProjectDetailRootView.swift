import SwiftUI
import AppKit
import DevHavenCore

struct ProjectDetailRootView: View {
    @Bindable var viewModel: NativeAppViewModel

    var body: some View {
        if let project = viewModel.selectedProject {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(project.name)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(NativeTheme.textPrimary)
                            Text(project.path)
                                .font(.caption)
                                .foregroundStyle(NativeTheme.textSecondary)
                                .textSelection(.enabled)
                        }
                        Spacer()
                        Button {
                            viewModel.closeDetailPanel()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(NativeTheme.textSecondary)
                                .frame(width: 24, height: 24)
                                .background(Color.white.opacity(0.05))
                                .clipShape(.circle)
                        }
                        .buttonStyle(.plain)
                    }

                    section("基础信息") {
                        detailRow("最近修改", formatSwiftDate(project.mtime))
                        detailRow("Git 提交", project.gitCommits > 0 ? "\(project.gitCommits) 次" : "非 Git 项目")
                        detailRow("最后检查", formatSwiftDate(project.checked))
                        detailRow("最后摘要", project.gitLastCommitMessage ?? "--")
                    }

                    section("标签") {
                        if project.tags.isEmpty {
                            Text("暂无可见标签")
                                .font(.caption)
                                .foregroundStyle(NativeTheme.textSecondary)
                        } else {
                            WrapHStack(project.tags, spacing: 8) { tag in
                                Text(tag)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(NativeTheme.accent.opacity(0.5))
                                    .clipShape(.rect(cornerRadius: 8))
                            }
                        }
                    }

                    section("备注") {
                        HStack {
                            Spacer()
                            Button("用 README 初始化") {
                                if let readme = viewModel.readmeFallback {
                                    viewModel.notesDraft = readme.content
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundStyle(NativeTheme.textSecondary)
                        }
                        TextEditor(text: $viewModel.notesDraft)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .foregroundStyle(NativeTheme.textPrimary)
                            .frame(minHeight: 130)
                            .padding(10)
                            .background(Color.white.opacity(0.04))
                            .clipShape(.rect(cornerRadius: 10))
                        HStack {
                            Spacer()
                            Button("保存备注") {
                                viewModel.saveNotes()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(NativeTheme.accent)
                        }
                    }

                    section("Todo") {
                        HStack {
                            TextField("记录项目 Todo（保存到 PROJECT_TODO.md）", text: $viewModel.todoDraft)
                                .textFieldStyle(.plain)
                                .foregroundStyle(NativeTheme.textPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color.white.opacity(0.04))
                                .clipShape(.rect(cornerRadius: 10))
                            Button("添加") {
                                viewModel.addTodoItem()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(NativeTheme.accent)
                        }
                        if viewModel.todoItems.isEmpty {
                            Text("暂无待办")
                                .font(.caption)
                                .foregroundStyle(NativeTheme.textSecondary)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(viewModel.todoItems) { item in
                                    HStack(alignment: .top, spacing: 10) {
                                        Toggle(isOn: Binding(
                                            get: { item.done },
                                            set: { _ in viewModel.toggleTodo(id: item.id) }
                                        )) {
                                            Text(item.text)
                                                .foregroundStyle(item.done ? NativeTheme.textSecondary : NativeTheme.textPrimary)
                                        }
                                        .toggleStyle(.checkbox)
                                        Spacer()
                                        Button(role: .destructive) {
                                            viewModel.removeTodo(id: item.id)
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(NativeTheme.textSecondary)
                                    }
                                    .padding(10)
                                    .background(Color.white.opacity(0.04))
                                    .clipShape(.rect(cornerRadius: 10))
                                }
                            }
                            HStack {
                                Spacer()
                                Button("保存 Todo") {
                                    viewModel.saveTodo()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(NativeTheme.accent)
                            }
                        }
                    }

                    section("快捷命令") {
                        if project.scripts.isEmpty {
                            Text("暂无快捷命令")
                                .font(.caption)
                                .foregroundStyle(NativeTheme.textSecondary)
                        } else {
                            VStack(spacing: 10) {
                                ForEach(project.scripts) { script in
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(script.name)
                                            .font(.headline)
                                            .foregroundStyle(NativeTheme.textPrimary)
                                        Text(script.start)
                                            .font(.caption.monospaced())
                                            .foregroundStyle(NativeTheme.textSecondary)
                                            .textSelection(.enabled)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(Color.white.opacity(0.04))
                                    .clipShape(.rect(cornerRadius: 10))
                                }
                            }
                        }
                    }

                    section("Markdown") {
                        if let readme = viewModel.readmeFallback {
                            Text(readme.content)
                                .font(.caption)
                                .foregroundStyle(NativeTheme.textPrimary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color.white.opacity(0.04))
                                .clipShape(.rect(cornerRadius: 10))
                        } else {
                            Text("未发现备注，也未找到 README.md 作为回退参考")
                                .font(.caption)
                                .foregroundStyle(NativeTheme.textSecondary)
                        }
                    }
                }
                .padding(18)
            }
            .frame(maxHeight: .infinity)
            .background(NativeTheme.panel)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(NativeTheme.border)
                    .frame(width: 1)
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(NativeTheme.textPrimary)
            content()
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .frame(width: 64, alignment: .leading)
                .foregroundStyle(NativeTheme.textSecondary)
            Text(value)
                .foregroundStyle(NativeTheme.textPrimary)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .font(.caption)
    }
}

private struct WrapHStack<Data: RandomAccessCollection, Content: View>: View where Data.Element: Hashable {
    let data: Data
    let spacing: CGFloat
    let content: (Data.Element) -> Content

    init(_ data: Data, spacing: CGFloat, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: spacing)], alignment: .leading, spacing: spacing) {
            ForEach(Array(data), id: \.self) { element in
                content(element)
            }
        }
    }
}
