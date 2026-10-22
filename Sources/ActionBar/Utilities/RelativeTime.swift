import Foundation

enum RelativeTime {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    static func format(_ date: Date, relativeTo now: Date = Date()) -> String {
        let minutes = Int(now.timeIntervalSince(date)) / 60
        let hours = minutes / 60
        let days = hours / 24

        if minutes < 1 {
            return "just now"
        } else if hours < 1 {
            return "\(minutes)m ago"
        } else if days < 1 {
            return "\(hours)h ago"
        } else if days < 30 {
            return "\(days)d ago"
        } else {
            return dateFormatter.string(from: date)
        }
    }
}
