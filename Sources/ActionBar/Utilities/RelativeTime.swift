import Foundation

enum RelativeTime {
    static func format(_ date: Date, relativeTo now: Date = Date()) -> String {
        let interval = now.timeIntervalSince(date)

        if interval < 0 {
            return "just now"
        }

        let seconds = Int(interval)
        let minutes = seconds / 60
        let hours = minutes / 60
        let days = hours / 24

        if seconds < 60 {
            return "just now"
        } else if minutes < 60 {
            return "\(minutes)m ago"
        } else if hours < 24 {
            return "\(hours)h ago"
        } else if days < 30 {
            return "\(days)d ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}
