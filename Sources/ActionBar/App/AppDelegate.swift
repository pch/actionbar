import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var windowObserver: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = GitHubIcon.makeAppIcon()
        UNUserNotificationCenter.current().delegate = self
        NotificationService.requestPermission()

        // Make the MenuBarExtra panel immune to "Show Desktop" / Exposé
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let panel = notification.object as? NSPanel else { return }
            panel.collectionBehavior.insert(
                [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            )
        }
    }

    // Show notifications even when the app is in the foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
