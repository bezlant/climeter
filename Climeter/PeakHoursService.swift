import Foundation

struct PeakHoursService {
    static let peakStartHour = 5
    static let peakEndHour = 11
    static let peakTimeZone = TimeZone(identifier: "America/Los_Angeles")!

    static func isPeakNow(at date: Date = Date()) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = peakTimeZone
        let weekday = calendar.component(.weekday, from: date)
        let hour = calendar.component(.hour, from: date)
        let isWeekday = (2...6).contains(weekday)
        return isWeekday && hour >= peakStartHour && hour < peakEndHour
    }

    static func peakEndTime(at date: Date = Date()) -> Date? {
        guard isPeakNow(at: date) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = peakTimeZone
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = peakEndHour
        components.minute = 0
        components.second = 0
        return calendar.date(from: components)
    }

    static func nextPeakStartTime(at date: Date = Date()) -> Date? {
        guard !isPeakNow(at: date) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = peakTimeZone

        var candidate = date
        for _ in 0..<8 {
            let weekday = calendar.component(.weekday, from: candidate)
            let hour = calendar.component(.hour, from: candidate)
            let isWeekday = (2...6).contains(weekday)

            if isWeekday && hour < peakStartHour {
                var components = calendar.dateComponents([.year, .month, .day], from: candidate)
                components.hour = peakStartHour
                components.minute = 0
                components.second = 0
                return calendar.date(from: components)
            }

            var dayStart = calendar.dateComponents([.year, .month, .day], from: candidate)
            dayStart.hour = 0
            dayStart.minute = 0
            dayStart.second = 0
            if let today = calendar.date(from: dayStart) {
                candidate = calendar.date(byAdding: .day, value: 1, to: today)!
            }
        }
        return nil
    }

    static func localTimeRangeString() -> String {
        let localTZ = TimeZone.current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = peakTimeZone

        let now = Date()
        var startComponents = calendar.dateComponents([.year, .month, .day], from: now)
        startComponents.hour = peakStartHour
        startComponents.minute = 0
        var endComponents = startComponents
        endComponents.hour = peakEndHour

        guard let startDate = calendar.date(from: startComponents),
              let endDate = calendar.date(from: endComponents) else {
            return "5 AM – 11 AM PT"
        }

        let formatter = DateFormatter()
        formatter.timeZone = localTZ
        formatter.dateFormat = "h:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let tzAbbr = localTZ.abbreviation(for: now) ?? localTZ.identifier
        return "\(formatter.string(from: startDate)) – \(formatter.string(from: endDate)) \(tzAbbr)"
    }
}
