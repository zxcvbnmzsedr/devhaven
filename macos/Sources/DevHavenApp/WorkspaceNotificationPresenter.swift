import AppKit
import UserNotifications
import DevHavenCore

private final class WorkspaceForegroundNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        _ = center
        _ = notification
        return [.banner, .sound]
    }
}

@MainActor
enum WorkspaceNotificationPresenter {
    private static let delegate = WorkspaceForegroundNotificationDelegate()

    static func presentIfNeeded(
        title: String,
        body: String,
        settings: AppSettings
    ) {
        guard settings.workspaceSystemNotificationsEnabled || settings.workspaceNotificationSoundEnabled else {
            return
        }

        if settings.workspaceSystemNotificationsEnabled {
            Task { @MainActor in
                await sendSystemNotification(title: title, body: body)
            }
            return
        }

        if settings.workspaceNotificationSoundEnabled {
            NSSound.beep()
        }
    }

    private static func sendSystemNotification(title: String, body: String) async {
        let center = configuredCenter()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            break
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
                guard granted else {
                    return
                }
            } catch {
                return
            }
        case .denied, .ephemeral:
            return
        @unknown default:
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    private static func configuredCenter() -> UNUserNotificationCenter {
        let center = UNUserNotificationCenter.current()
        if center.delegate !== delegate {
            center.delegate = delegate
        }
        return center
    }
}
