import SwiftUI
import DevHavenCore

struct WorkspaceTabBarView: View {
    let tabs: [WorkspacePresentedTabItem]
    let canSplit: Bool
    let onSelectTab: (WorkspacePresentedTabSelection) -> Void
    let onCloseTab: (WorkspacePresentedTabSelection) -> Void
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
                    title: "新建标签页",
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
                    Text(tab.title)
                        .lineLimit(1)
                }
                .font(.callout.weight(.semibold))
                .foregroundStyle(isSelected ? NativeTheme.textPrimary : NativeTheme.textSecondary)
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
