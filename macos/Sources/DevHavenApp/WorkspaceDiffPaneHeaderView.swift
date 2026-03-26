import AppKit
import SwiftUI
import DevHavenCore

struct WorkspaceDiffPaneHeaderView: View {
    let descriptor: WorkspaceDiffPaneDescriptor

    var body: some View {
        let metadata = descriptor.metadata
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Text(metadata.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NativeTheme.textPrimary)

                Spacer(minLength: 8)

                if !metadata.copyPayloads.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(metadata.copyPayloads) { payload in
                            Button(payload.label) {
                                copyToPasteboard(payload.value)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }

            if let path = metadata.path {
                Text(path)
                    .font(.caption.monospaced())
                    .foregroundStyle(NativeTheme.textSecondary)
                    .lineLimit(1)
            }

            if let oldPath = metadata.oldPath {
                Text("Renamed from \(oldPath)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(NativeTheme.textSecondary)
                    .lineLimit(1)
            }

            if !metadata.primaryDetails.isEmpty {
                metadataDetailRow(metadata.primaryDetails)
            }

            if !metadata.secondaryDetails.isEmpty {
                metadataDetailRow(metadata.secondaryDetails)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NativeTheme.surface)
        .help(metadata.tooltip ?? metadata.path ?? metadata.title)
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

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
