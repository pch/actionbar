import Foundation
import UserNotifications

enum NotificationService {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func sendCompletionNotification(run: WorkflowRun) {
        let status = RunStatus(from: run)
        let content = UNMutableNotificationContent()
        content.title = "\(status.label): \(run.displayTitle ?? run.name ?? "Workflow")"
        content.body = "\(run.repositoryFullName) · \(run.headBranch ?? "")"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "run-\(run.id)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
}
