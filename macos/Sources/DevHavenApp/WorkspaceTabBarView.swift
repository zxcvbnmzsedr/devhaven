import SwiftUI
import DevHavenCore

struct WorkspaceTabBarView: View {
    let tabs: [WorkspacePresentedTabItem]
    let canSplit: Bool
    let onSelectTab: (WorkspacePresentedTabSelection) -> Void
    let onCloseTab: (WorkspacePresentedTabSelection) -> Void
    let onPromoteEditorPreview: (String) -> Void
    let onSetEditorPinned: (String, Bool) -> Void
    let onCloseOtherEditorTabs: (String) -> Void
    let onCloseEditorTabsToRight: (String) -> Void
    let onCreateTab: () -> Void
    let onSplitHorizontally: () -> Void
    let onSplitVertically: () -> Void

    var body: some View {
        let isDiffTabSelected = tabs.contains { tab in
            tab.isSelected && {
                if case .diff = tab.selection {
                    return true
                }
                return false
            }()
        }

        HStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tabs) { tab in
                        tabChip(tab)
                    }
                }
                .padding(.vertical, 2)
            }

            HStack(spacing: 8) {
                toolbarButton(
                    title: "新建工作区标签",
                    systemImage: "plus",
                    action: onCreateTab
                )
                toolbarButton(
                    title: "左右分屏",
                    systemImage: "square.split.2x1",
                    action: onSplitVertically,
                    disabled: !canSplit || isDiffTabSelected
                )
                toolbarButton(
                    title: "上下分屏",
                    systemImage: "rectangle.split.1x2",
                    action: onSplitHorizontally,
                    disabled: !canSplit || isDiffTabSelected
                )
            }
        }
        .padding(.vertical, 6)
    }

    private func tabChip(_ tab: WorkspacePresentedTabItem) -> some View {
        let isSelected = tab.isSelected
        let semantics = WorkspaceTabChipSemantics.resolve(for: tab)
        let editorTabContext = editorTabContext(for: tab)

        return HStack(spacing: 8) {
            Button {
                onSelectTab(tab.selection)
            } label: {
                HStack(spacing: 6) {
                    switch tab.selection {
                    case .terminal:
                        Image(systemName: "terminal")
                            .font(.caption)
                    case .editor:
                        Image(systemName: "doc.text")
                            .font(.caption)
                    case .diff:
                        Image(systemName: "square.split.2x1")
                            .font(.caption)
                    }
                    if let statusSymbol = semantics.leadingStatusSystemImage {
                        Image(systemName: statusSymbol)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(
                                isSelected
                                    ? NativeTheme.textPrimary
                                    : NativeTheme.textSecondary.opacity(semantics.leadingStatusOpacity)
                            )
                    }
                    Group {
                        if semantics.usesItalicTitle {
                            Text(tab.title)
                                .italic()
                        } else {
                            Text(tab.title)
                        }
                    }
                    .lineLimit(1)
                    if let badgeTitle = semantics.badgeTitle {
                        Text(badgeTitle)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(isSelected ? NativeTheme.textPrimary : NativeTheme.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(isSelected ? NativeTheme.accent.opacity(0.18) : NativeTheme.border.opacity(0.5))
                            )
                    }
                }
                .font(.callout.weight(.semibold))
                .foregroundStyle(
                    isSelected
                        ? NativeTheme.textPrimary
                        : NativeTheme.textSecondary.opacity(semantics.titleOpacity)
                )
            }
            .buttonStyle(.plain)

            Button {
                onCloseTab(tab.selection)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isSelected ? NativeTheme.textPrimary : NativeTheme.textSecondary)
                    .padding(4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? NativeTheme.elevated : NativeTheme.surface)
        .clipShape(.rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? NativeTheme.accent.opacity(0.65) : NativeTheme.border, lineWidth: 1)
        )
        .contextMenu {
            switch tab.selection {
            case let .editor(tabID):
                if tab.isPreview {
                    Button("转为常规标签页") {
                        onPromoteEditorPreview(tabID)
                    }
                }

                if tab.isPinned {
                    Button("取消固定标签页") {
                        onSetEditorPinned(tabID, false)
                    }
                } else {
                    Button(tab.isPreview ? "固定预览标签页" : "固定标签页") {
                        onSetEditorPinned(tabID, true)
                    }
                }

                Divider()

                Button("关闭其他标签页") {
                    onCloseOtherEditorTabs(tabID)
                }
                .disabled(editorTabContext.otherEditorTabCount == 0)

                Button("关闭右侧标签页") {
                    onCloseEditorTabsToRight(tabID)
                }
                .disabled(editorTabContext.editorTabsToRightCount == 0)

                Divider()

                Button("关闭") {
                    onCloseTab(tab.selection)
                }
            case .terminal, .diff:
                Button("关闭") {
                    onCloseTab(tab.selection)
                }
            }
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                guard case let .editor(tabID) = tab.selection, tab.isPreview else {
                    return
                }
                onPromoteEditorPreview(tabID)
            }
        )
    }

    private func editorTabContext(for tab: WorkspacePresentedTabItem) -> WorkspaceEditorTabContext {
        let editorTabs = tabs.compactMap { candidate -> WorkspacePresentedTabItem? in
            guard case .editor = candidate.selection else {
                return nil
            }
            return candidate
        }
        guard case let .editor(tabID) = tab.selection,
              let editorIndex = editorTabs.firstIndex(where: { $0.id == tabID })
        else {
            return WorkspaceEditorTabContext(otherEditorTabCount: 0, editorTabsToRightCount: 0)
        }
        return WorkspaceEditorTabContext(
            otherEditorTabCount: max(0, editorTabs.count - 1),
            editorTabsToRightCount: max(0, editorTabs.count - editorIndex - 1)
        )
    }

    private func toolbarButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void,
        disabled: Bool = false
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.callout.weight(.semibold))
                .foregroundStyle(disabled ? NativeTheme.textSecondary.opacity(0.5) : NativeTheme.textPrimary)
                .frame(width: 30, height: 30)
                .background(NativeTheme.surface)
                .clipShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(title)
    }
}

struct WorkspaceTabChipSemantics: Equatable {
    var leadingStatusSystemImage: String?
    var leadingStatusOpacity: Double
    var badgeTitle: String?
    var usesItalicTitle: Bool
    var titleOpacity: Double

    static func resolve(for tab: WorkspacePresentedTabItem) -> Self {
        if tab.isPinned {
            return WorkspaceTabChipSemantics(
                leadingStatusSystemImage: "pin.fill",
                leadingStatusOpacity: 1,
                badgeTitle: nil,
                usesItalicTitle: false,
                titleOpacity: 1
            )
        }

        if tab.isPreview {
            return WorkspaceTabChipSemantics(
                leadingStatusSystemImage: nil,
                leadingStatusOpacity: 1,
                badgeTitle: "预览",
                usesItalicTitle: true,
                titleOpacity: 0.82
            )
        }

        return WorkspaceTabChipSemantics(
            leadingStatusSystemImage: nil,
            leadingStatusOpacity: 1,
            badgeTitle: nil,
            usesItalicTitle: false,
            titleOpacity: 1
        )
    }
}

private struct WorkspaceEditorTabContext: Equatable {
    var otherEditorTabCount: Int
    var editorTabsToRightCount: Int
}
