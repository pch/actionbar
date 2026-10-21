import AppKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        NotificationService.requestPermission()

        // Make the MenuBarExtra panel immune to "Show Desktop" / Exposé
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
    }

    // Windows become key on the main thread, so this is called there.
    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel, !(panel is NSOpenPanel) else { return }
        panel.collectionBehavior.insert([.canJoinAllSpaces, .stationary, .fullScreenAuxiliary])
    }

    // UserNotifications doesn't promise to call its delegate on the main thread, so these are
    // nonisolated rather than inheriting the app delegate's main actor isolation.

    // Show notifications even when the app is in the foreground
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // Open the workflow run in the browser when the notification is clicked
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let urlString = response.notification.request.content.userInfo["url"] as? String,
           let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
        completionHandler()
    }
}
