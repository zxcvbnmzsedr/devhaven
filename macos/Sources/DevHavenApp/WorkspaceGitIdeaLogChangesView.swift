import SwiftUI
import DevHavenCore

struct WorkspaceGitIdeaLogChangesView: View {
    @Bindable var viewModel: WorkspaceGitLogViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            paneHeader(title: "变更", subtitle: changeCountLabel)
            Divider()
                .overlay(NativeTheme.border)

            if viewModel.isLoadingSelectedCommitDetail && viewModel.selectedCommitDetail == nil {
                ProgressView("正在加载变更…")
                    .tint(NativeTheme.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let detail = viewModel.selectedCommitDetail {
                List(detail.files) { file in
                    fileRow(for: file)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .background(NativeTheme.window)
            } else {
                ContentUnavailableView(
                    "选择一个提交",
                    systemImage: "list.bullet.rectangle.portrait",
                    description: Text("选择提交后，这里会展示该提交的文件变更。")
                )
                .foregroundStyle(NativeTheme.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var changeCountLabel: String {
        if let detail = viewModel.selectedCommitDetail {
            return "\(detail.files.count) 项"
        }
        return "未选择"
    }

    private func paneHeader(title: String, subtitle: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(NativeTheme.textPrimary)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(NativeTheme.textSecondary)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(NativeTheme.surface)
    }

    private func fileRow(for file: WorkspaceGitCommitFileChange) -> some View {
        Button {
            viewModel.selectCommitFile(file.path)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon(for: file.status))
                    .font(.caption)
                    .foregroundStyle(color(for: file.status))
                    .frame(width: 12, height: 16, alignment: .top)

                VStack(alignment: .leading, spacing: 2) {
                    Text(primaryFileName(for: file))
                        .font(.callout.monospaced())
                        .foregroundStyle(NativeTheme.textPrimary)
                        .lineLimit(1)
                    if let subtitle = fileSubtitle(for: file) {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(NativeTheme.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                Text(file.status.rawValue.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(NativeTheme.textSecondary)
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(viewModel.selectedFilePath == file.path ? NativeTheme.accent.opacity(0.14) : Color.clear)
            .clipShape(.rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func fileSubtitle(for file: WorkspaceGitCommitFileChange) -> String? {
        secondaryPathSubtitle(for: file)
    }

    private func primaryFileName(for file: WorkspaceGitCommitFileChange) -> String {
        let fileName = (file.path as NSString).lastPathComponent
        return fileName.isEmpty ? file.path : fileName
    }

    private func secondaryPathSubtitle(for file: WorkspaceGitCommitFileChange) -> String? {
        var parts = [String]()
        let parentPath = (file.path as NSString).deletingLastPathComponent
        if !parentPath.isEmpty && parentPath != file.path {
            parts.append(parentPath)
        }

        switch file.status {
        case .renamed:
            if let oldPath = file.oldPath {
                parts.append("从 \((oldPath as NSString).lastPathComponent) 重命名")
            }
            return parts.isEmpty ? "已重命名" : parts.joined(separator: " · ")
        case .copied:
            if let oldPath = file.oldPath {
                parts.append("从 \((oldPath as NSString).lastPathComponent) 复制")
            }
            return parts.isEmpty ? "已复制" : parts.joined(separator: " · ")
        case .typeChanged:
            parts.append("文件类型已变化")
            return parts.joined(separator: " · ")
        case .unmerged:
            parts.append("存在未解决冲突")
            return parts.joined(separator: " · ")
        default:
            return parts.isEmpty ? nil : parts.joined(separator: " / ")
        }
    }

    private func color(for status: WorkspaceGitCommitFileStatus) -> Color {
        switch status {
        case .added:
            return .green
        case .modified:
            return NativeTheme.accent
        case .deleted:
            return .red
        case .renamed, .copied:
            return .orange
        case .typeChanged, .unmerged, .unknown:
            return NativeTheme.textSecondary
        }
    }

    private func icon(for status: WorkspaceGitCommitFileStatus) -> String {
        switch status {
        case .added:
            return "plus.square.fill"
        case .modified:
            return "pencil.line"
        case .deleted:
            return "trash.fill"
        case .renamed:
            return "arrow.left.arrow.right.square"
        case .copied:
            return "square.on.square"
        case .typeChanged:
            return "square.3.layers.3d"
        case .unmerged:
            return "exclamationmark.triangle.fill"
        case .unknown:
            return "questionmark.square"
        }
    }
}
