import Foundation

struct SleepObservation {
    let hours: Double
    let night: String

    init(hours: Double, endingAt: Date, calendar: Calendar = .current) {
        self.hours = hours
        let date = calendar.dateComponents([.year, .month, .day], from: endingAt)
        night = "\(date.year ?? 0)-\(date.month ?? 0)-\(date.day ?? 0)"
    }

    static func aggregate(_ intervals: [DateInterval], before date: Date) -> Self? {
        let cutoff = date.addingTimeInterval(-24 * 3600)
        let clipped = intervals.compactMap { interval -> DateInterval? in
            let start = max(interval.start, cutoff)
            let end = min(interval.end, date)
            guard start < end else { return nil }
            return DateInterval(start: start, end: end)
        }.sorted { $0.start < $1.start }
        guard var current = clipped.first else { return nil }
        var seconds = 0.0
        for interval in clipped.dropFirst() {
            if interval.start <= current.end {
                current = DateInterval(start: current.start, end: max(current.end, interval.end))
            } else {
                seconds += current.duration
                current = interval
            }
        }
        return Self(hours: (seconds + current.duration) / 3600, endingAt: current.end)
    }
}
