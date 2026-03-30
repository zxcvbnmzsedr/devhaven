import SwiftUI
import DevHavenCore

struct WorkspaceEditorSplitContentView: View {
    @Bindable var viewModel: NativeAppViewModel
    let projectPath: String
    let presentation: WorkspaceEditorPresentationState

    var body: some View {
        let groups = Array(presentation.groups.prefix(2))

        Group {
            if groups.count >= 2, let splitAxis = presentation.splitAxis {
                WorkspaceSplitView(
                    direction: splitAxis,
                    ratio: presentation.splitRatio,
                    onRatioChange: { ratio in
                        viewModel.updateWorkspaceEditorSplitRatio(ratio, in: projectPath)
                    }
                ) {
                    editorPane(for: groups[0])
                } trailing: {
                    editorPane(for: groups[1])
                }
            } else if let group = groups.first {
                editorPane(for: group)
            } else {
                emptyPane
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NativeTheme.window)
    }

    @ViewBuilder
    private func editorPane(for group: WorkspaceEditorGroupState) -> some View {
        let tabs = group.tabIDs.compactMap { viewModel.workspaceEditorTabState(for: projectPath, tabID: $0) }
        let selectedTabID = group.selectedTabID ?? group.tabIDs.last
        let isActive = presentation.activeGroupID == group.id
        let oppositeGroupID = presentation.groups.first(where: { $0.id != group.id })?.id

        VStack(spacing: 0) {
            paneToolbar(
                group: group,
                tabs: tabs,
                selectedTabID: selectedTabID,
                isActive: isActive,
                oppositeGroupID: oppositeGroupID
            )
            Divider()

            Group {
                if let selectedTabID,
                   viewModel.workspaceEditorTabState(for: projectPath, tabID: selectedTabID) != nil {
                    WorkspaceEditorTabView(
                        viewModel: viewModel,
                        projectPath: projectPath,
                        tabID: selectedTabID
                    )
                    .id("workspace-editor-group-\(group.id)-\(selectedTabID)")
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            viewModel.selectWorkspaceEditorGroup(group.id, in: projectPath)
                            viewModel.selectWorkspacePresentedTab(.editor(selectedTabID), in: projectPath)
                        }
                    )
                } else {
                    ContentUnavailableView(
                        "空白编辑器分栏",
                        systemImage: "square.split.2x1",
                        description: Text("点击此处激活该分栏，然后从 Project 树或顶部标签页打开文件。")
                    )
                    .foregroundStyle(NativeTheme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.selectWorkspaceEditorGroup(group.id, in: projectPath)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NativeTheme.window)
        .overlay {
            RoundedRectangle(cornerRadius: 0)
                .stroke(
                    isActive ? NativeTheme.accent.opacity(0.7) : NativeTheme.border,
                    lineWidth: isActive ? 2 : 1
                )
        }
    }

    private func paneToolbar(
        group: WorkspaceEditorGroupState,
        tabs: [WorkspaceEditorTabState],
        selectedTabID: String?,
        isActive: Bool,
        oppositeGroupID: String?
    ) -> some View {
        HStack(spacing: 12) {
            Button {
                viewModel.selectWorkspaceEditorGroup(group.id, in: projectPath)
                if let selectedTabID {
                    viewModel.selectWorkspacePresentedTab(.editor(selectedTabID), in: projectPath)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.split.2x1")
                    Text(isActive ? "活动分栏" : "编辑器分栏")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(isActive ? NativeTheme.textPrimary : NativeTheme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(isActive ? NativeTheme.elevated : NativeTheme.surface)
                .clipShape(.rect(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if tabs.isEmpty {
                        Text("此分栏暂无文件")
                            .font(.caption)
                            .foregroundStyle(NativeTheme.textSecondary)
                            .padding(.vertical, 6)
                    } else {
                        ForEach(tabs) { tab in
                            tabChip(
                                tab: tab,
                                isSelected: tab.id == selectedTabID,
                                oppositeGroupID: oppositeGroupID
                            )
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            Spacer(minLength: 0)

            if let selectedTabID,
               let oppositeGroupID {
                toolbarButton(
                    title: "移动到另一个分栏",
                    systemImage: "arrow.left.arrow.right.square",
                    action: {
                        viewModel.moveWorkspaceEditorTab(
                            selectedTabID,
                            toGroup: oppositeGroupID,
                            in: projectPath
                        )
                    }
                )
            }

            if presentation.groups.count > 1 {
                toolbarButton(
                    title: "关闭此分栏",
                    systemImage: "rectangle.split.2x1.slash",
                    action: {
                        viewModel.closeWorkspaceEditorGroup(group.id, in: projectPath)
                    }
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(NativeTheme.window)
    }

    private func tabChip(
        tab: WorkspaceEditorTabState,
        isSelected: Bool,
        oppositeGroupID: String?
    ) -> some View {
        HStack(spacing: 6) {
            Button {
                viewModel.selectWorkspaceEditorGroup(groupID(for: tab.id), in: projectPath)
                viewModel.selectWorkspacePresentedTab(.editor(tab.id), in: projectPath)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: tab.isPinned ? "pin.fill" : "doc.text")
                        .font(tab.isPinned ? .caption2.weight(.semibold) : .caption)
                    Group {
                        if tab.isPreview {
                            Text(tab.isDirty ? "● \(tab.title)" : tab.title)
                                .italic()
                        } else {
                            Text(tab.isDirty ? "● \(tab.title)" : tab.title)
                        }
                    }
                    .lineLimit(1)
                    if tab.isPreview {
                        Text("预览")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(NativeTheme.border.opacity(0.5)))
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? NativeTheme.textPrimary : NativeTheme.textSecondary)
            }
            .buttonStyle(.plain)

            Button {
                viewModel.closeWorkspaceEditorTab(tab.id, in: projectPath)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(isSelected ? NativeTheme.textPrimary : NativeTheme.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isSelected ? NativeTheme.elevated : NativeTheme.surface)
        .clipShape(.rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? NativeTheme.accent.opacity(0.65) : NativeTheme.border, lineWidth: 1)
        )
        .contextMenu {
            if tab.isPreview {
                Button("转为常规标签页") {
                    viewModel.promoteWorkspaceEditorTabToRegular(tab.id, in: projectPath)
                }
            }

            if tab.isPinned {
                Button("取消固定标签页") {
                    viewModel.setWorkspaceEditorTabPinned(false, tabID: tab.id, in: projectPath)
                }
            } else {
                Button(tab.isPreview ? "固定预览标签页" : "固定标签页") {
                    viewModel.setWorkspaceEditorTabPinned(true, tabID: tab.id, in: projectPath)
                }
            }

            if let oppositeGroupID {
                Divider()
                Button("移动到另一个分栏") {
                    viewModel.moveWorkspaceEditorTab(tab.id, toGroup: oppositeGroupID, in: projectPath)
                }
            }

            Divider()
            Button("关闭") {
                viewModel.closeWorkspaceEditorTab(tab.id, in: projectPath)
            }
        }
    }

    private func groupID(for tabID: String) -> String {
        presentation.groups.first(where: { $0.tabIDs.contains(tabID) })?.id ?? presentation.activeGroupID ?? "workspace-editor-group:default"
    }

    private func toolbarButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.callout.weight(.semibold))
                .foregroundStyle(NativeTheme.textPrimary)
                .frame(width: 30, height: 30)
                .background(NativeTheme.surface)
                .clipShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(title)
    }

    private var emptyPane: some View {
        ContentUnavailableView(
            "暂无编辑器分栏",
            systemImage: "square.split.2x1",
            description: Text("请先从 Project 树打开文件。")
        )
        .foregroundStyle(NativeTheme.textSecondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
