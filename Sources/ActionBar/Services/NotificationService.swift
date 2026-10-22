import Foundation
import UserNotifications

enum NotificationService {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func sendCompletionNotification(run: WorkflowRun) {
        let content = UNMutableNotificationContent()
        content.title = "\(RunStatus(from: run).label): \(run.title)"
        content.body = "\(run.repositoryFullName) · \(run.headBranch ?? "")"
        content.sound = .default
        content.userInfo = ["url": run.htmlUrl]

        let request = UNNotificationRequest(
            identifier: "run-\(run.id)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
}
