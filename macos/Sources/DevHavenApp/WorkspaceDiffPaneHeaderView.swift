import AppKit
import SwiftUI
import DevHavenCore

struct WorkspaceDiffPaneHeaderView: View {
    let descriptor: WorkspaceDiffPaneDescriptor

    var body: some View {
        let metadata = descriptor.metadata
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                titleBadge(metadata.title)

                VStack(alignment: .leading, spacing: 2) {
                    Text(primaryPathLabel(for: metadata))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NativeTheme.textPrimary)
                        .lineLimit(1)

                    if let path = metadata.path {
                        Text(path)
                            .font(.caption2.monospaced())
                            .foregroundStyle(NativeTheme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 8)

                if !metadata.copyPayloads.isEmpty {
                    Menu {
                        ForEach(metadata.copyPayloads) { payload in
                            Button(payload.label) {
                                copyToPasteboard(payload.value)
                            }
                        }
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(NativeTheme.textSecondary)
                    }
                    .menuStyle(.borderlessButton)
                    .help("复制元数据")
                }
            }

            if let oldPath = metadata.oldPath {
                Text("Renamed from \(oldPath)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(NativeTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if !metadata.primaryDetails.isEmpty || !metadata.secondaryDetails.isEmpty {
                HStack(spacing: 6) {
                    metadataDetailRow(metadata.primaryDetails)
                    if !metadata.primaryDetails.isEmpty && !metadata.secondaryDetails.isEmpty {
                        Circle()
                            .fill(NativeTheme.border.opacity(0.9))
                            .frame(width: 3, height: 3)
                    }
                    metadataDetailRow(metadata.secondaryDetails)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NativeTheme.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(NativeTheme.border.opacity(0.8))
                .frame(height: 1)
        }
        .help(metadata.tooltip ?? metadata.path ?? metadata.title)
    }

    private func primaryPathLabel(for metadata: WorkspaceDiffPaneMetadata) -> String {
        guard let path = metadata.path else {
            return metadata.title
        }
        let fileName = URL(fileURLWithPath: path).lastPathComponent
        return fileName.isEmpty ? path : fileName
    }

    private func titleBadge(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(roleBadgeForeground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(roleBadgeBackground)
            .clipShape(.capsule)
    }

    private func metadataDetailRow(_ items: [String]) -> some View {
        HStack(spacing: 6) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.caption2.monospaced())
                    .foregroundStyle(NativeTheme.textSecondary)
            }
        }
    }

    private var roleBadgeBackground: Color {
        switch descriptor.role {
        case .left:
            return NativeTheme.warning.opacity(0.18)
        case .right:
            return NativeTheme.accent.opacity(0.16)
        case .ours:
            return NativeTheme.warning.opacity(0.18)
        case .base:
            return NativeTheme.border.opacity(0.45)
        case .theirs:
            return NativeTheme.accent.opacity(0.16)
        case .result:
            return NativeTheme.success.opacity(0.16)
        }
    }

    private var roleBadgeForeground: Color {
        switch descriptor.role {
        case .base:
            return NativeTheme.textSecondary
        case .result:
            return NativeTheme.success
        case .left, .ours:
            return NativeTheme.warning
        case .right, .theirs:
            return NativeTheme.accent
        }
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
