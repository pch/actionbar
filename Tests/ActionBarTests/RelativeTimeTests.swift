import Foundation
import Testing

struct RelativeTimeTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func format(secondsAgo: TimeInterval) -> String {
        RelativeTime.format(now.addingTimeInterval(-secondsAgo), relativeTo: now)
    }

    @Test func underAMinuteIsJustNow() {
        #expect(format(secondsAgo: 0) == "just now")
        #expect(format(secondsAgo: 59) == "just now")
    }

    @Test func futureDatesAreJustNow() {
        #expect(format(secondsAgo: -120) == "just now")
    }

    @Test func minutes() {
        #expect(format(secondsAgo: 60) == "1m ago")
        #expect(format(secondsAgo: 59 * 60 + 59) == "59m ago")
    }

    @Test func hours() {
        #expect(format(secondsAgo: 60 * 60) == "1h ago")
        #expect(format(secondsAgo: 23 * 60 * 60 + 59 * 60) == "23h ago")
    }

    @Test func days() {
        #expect(format(secondsAgo: 24 * 60 * 60) == "1d ago")
        #expect(format(secondsAgo: 29 * 24 * 60 * 60) == "29d ago")
    }

    @Test func thirtyDaysOrMoreShowsTheDate() {
        let date = now.addingTimeInterval(-30 * 24 * 60 * 60)
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        #expect(RelativeTime.format(date, relativeTo: now) == formatter.string(from: date))
    }
}
