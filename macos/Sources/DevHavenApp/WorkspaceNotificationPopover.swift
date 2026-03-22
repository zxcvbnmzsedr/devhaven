import SwiftUI
import DevHavenCore

struct WorkspaceNotificationPopoverButton<Label: View>: View {
    let notifications: [WorkspaceTerminalNotification]
    let onFocusNotification: (WorkspaceTerminalNotification) -> Void
    @ViewBuilder let label: () -> Label

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented) {
            WorkspaceNotificationPopoverView(
                notifications: notifications,
                onFocusNotification: { notification in
                    isPresented = false
                    onFocusNotification(notification)
                }
            )
        }
    }
}

struct WorkspaceNotificationPopoverView: View {
    let notifications: [WorkspaceTerminalNotification]
    let onFocusNotification: (WorkspaceTerminalNotification) -> Void

    var body: some View {
        let count = notifications.count
        VStack(alignment: .leading, spacing: 10) {
            Text("工作区通知")
                .font(.headline)
                .foregroundStyle(NativeTheme.textPrimary)
            Text("\(count) 条通知")
                .font(.caption)
                .foregroundStyle(NativeTheme.textSecondary)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(notifications) { notification in
                        Button {
                            onFocusNotification(notification)
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "bell")
                                    .foregroundStyle(notification.isRead ? NativeTheme.textSecondary : NativeTheme.warning)
                                Text(notification.content.isEmpty ? "返回对应窗格" : notification.content)
                                    .font(.caption)
                                    .foregroundStyle(notification.isRead ? NativeTheme.textSecondary : NativeTheme.textPrimary)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(10)
                            .background(NativeTheme.elevated)
                            .clipShape(.rect(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .help(notification.content.isEmpty ? "定位到对应终端窗格" : notification.content)
                    }
                }
            }
        }
        .padding(14)
        .frame(minWidth: 280, maxWidth: 420, maxHeight: 360)
        .background(NativeTheme.surface)
    }
}
