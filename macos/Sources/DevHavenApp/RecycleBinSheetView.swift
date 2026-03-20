import SwiftUI
import DevHavenCore

struct RecycleBinSheetView: View {
    let items: [NativeAppViewModel.RecycleBinItem]
    let onRestore: (NativeAppViewModel.RecycleBinItem) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("回收站")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("关闭") {
                    onClose()
                }
            }

            if items.isEmpty {
                ContentUnavailableView(
                    "回收站为空",
                    systemImage: "trash",
                    description: Text("当前没有被隐藏的项目。")
                )
            } else {
                List(items) { item in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name)
                                .font(.headline)
                            Text(item.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if item.missing {
                                Text("该路径当前不在 projects.json 缓存中，将仅从 recycleBin 中移除。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("恢复") {
                            onRestore(item)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.inset)
            }
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 420)
    }
}
