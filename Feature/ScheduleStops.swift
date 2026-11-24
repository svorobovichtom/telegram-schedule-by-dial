import UIKit

/// One choice on the dial: a short mark on the ring, the moment it sends at, and how the hint says it.
struct ScheduleStop: Equatable {
    enum Mark: Equatable {
        case text(String)
        /// An SF Symbol, for the times of day ("tonight", "tomorrow morning") that read faster as a picture.
        case symbol(String)
    }

    let mark: Mark
    /// nil for "Custom": Telegram's own date and time picker opens instead.
    let date: Date?
    /// The hint's first line: "in 15 min", "tonight", "Custom".
    let relative: String

    var isCustom: Bool { date == nil }

    /// What the dial offers, in the order of the ring (from the left of Send up to above it, nearest first): the
    /// presets people pick most, then tonight and tomorrow morning, and last "Custom" for any other moment. Tonight
    /// drops out once it is late.
    static func stops(from now: Date, calendar: Calendar = .current) -> [ScheduleStop] {
        var stops = [
            ScheduleStop(mark: .text("15m"), date: now.addingTimeInterval(15 * 60), relative: "in 15 min"),
            ScheduleStop(mark: .text("30m"), date: now.addingTimeInterval(30 * 60), relative: "in 30 min"),
            ScheduleStop(mark: .text("1h"), date: now.addingTimeInterval(60 * 60), relative: "in 1 hour"),
            ScheduleStop(mark: .text("3h"), date: now.addingTimeInterval(3 * 60 * 60), relative: "in 3 hours"),
        ]
        let startOfToday = calendar.startOfDay(for: now)
        if let tonight = calendar.date(byAdding: .hour, value: 21, to: startOfToday),
           tonight.timeIntervalSince(now) > 3.5 * 60 * 60 {
            stops.append(ScheduleStop(mark: .symbol("moon.fill"), date: tonight, relative: "tonight"))
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday),
           let morning = calendar.date(byAdding: .hour, value: 9, to: tomorrow) {
            stops.append(ScheduleStop(mark: .symbol("sun.horizon.fill"), date: morning, relative: "tomorrow morning"))
        }
        stops.append(ScheduleStop(mark: .symbol("calendar"), date: nil, relative: "Custom"))
        return stops
    }

    /// The hint's second line: "today at 19:47", "tomorrow at 09:00"; for Custom what it does.
    func detail(now: Date) -> String {
        guard let date else { return "pick date and time" }
        return Self.phrase(for: date, now: now)
    }

    /// Worded like the schedule picker's button, without "Send": "today at 19:47", "on Nov 19 at 09:00".
    static func phrase(for date: Date, now: Date, calendar: Calendar = .current) -> String {
        let time = timeFormatter.string(from: date)
        if calendar.isDate(date, inSameDayAs: now) { return "today at \(time)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "tomorrow at \(time)"
        }
        return "on \(dayFormatter.string(from: date)) at \(time)"
    }

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM d"
        return f
    }()
}
