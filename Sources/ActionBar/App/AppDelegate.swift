import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var windowObserver: Any?
    private var configuredPanels = NSHashTable<NSPanel>.weakObjects()

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        NotificationService.requestPermission()

        // Make the MenuBarExtra panel immune to "Show Desktop" / Exposé
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let panel = notification.object as? NSPanel else { return }
            guard !panel.isKind(of: NSOpenPanel.self) else { return }
            guard let self, !self.configuredPanels.contains(panel) else { return }
            panel.collectionBehavior.insert(
                [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            )
            self.configuredPanels.add(panel)
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

    // Open the workflow run in the browser when the notification is clicked
    func userNotificationCenter(
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
