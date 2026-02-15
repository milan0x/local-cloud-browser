import Foundation

enum ScheduleExpressionHelper {

    // MARK: - Human-Readable Translation

    static func humanReadable(_ expr: String) -> String? {
        let trimmed = expr.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("rate(") && trimmed.hasSuffix(")") {
            return parseRate(trimmed)
        } else if trimmed.hasPrefix("cron(") && trimmed.hasSuffix(")") {
            return parseCron(trimmed)
        } else if trimmed.hasPrefix("at(") && trimmed.hasSuffix(")") {
            return parseAt(trimmed)
        }
        return nil
    }

    private static func parseRate(_ expr: String) -> String? {
        // rate(5 minutes), rate(1 hour), rate(2 days)
        let inner = String(expr.dropFirst(5).dropLast(1)).trimmingCharacters(in: .whitespaces)
        let parts = inner.split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        guard let value = Int(parts[0]) else { return nil }
        let unit = String(parts[1]).lowercased()

        if value == 1 {
            switch unit {
            case "minute", "minutes": return "Every minute"
            case "hour", "hours": return "Every hour"
            case "day", "days": return "Every day"
            default: return "Every 1 \(unit)"
            }
        } else {
            let unitSingular: String
            switch unit {
            case "minutes", "minute": unitSingular = "minutes"
            case "hours", "hour": unitSingular = "hours"
            case "days", "day": unitSingular = "days"
            default: unitSingular = unit
            }
            return "Every \(value) \(unitSingular)"
        }
    }

    private static func parseCron(_ expr: String) -> String? {
        // cron(minutes hours day-of-month month day-of-week year)
        let inner = String(expr.dropFirst(5).dropLast(1)).trimmingCharacters(in: .whitespaces)
        let fields = inner.split(separator: " ").map(String.init)
        guard fields.count == 6 else { return nil }

        let minutes = fields[0]
        let hours = fields[1]
        let dayOfMonth = fields[2]
        let month = fields[3]
        let dayOfWeek = fields[4]
        // year = fields[5]

        let timeStr: String
        if let h = Int(hours), let m = Int(minutes) {
            timeStr = String(format: "%02d:%02d", h, m)
        } else if hours == "*" && minutes == "*" {
            timeStr = "every minute"
        } else if let m = Int(minutes), hours == "*" {
            timeStr = "minute \(m) of every hour"
        } else {
            timeStr = "\(hours):\(minutes)"
        }

        // Simple patterns
        if dayOfMonth == "*" && month == "*" && dayOfWeek == "?" {
            if hours != "*" && minutes != "*" {
                return "Every day at \(timeStr) UTC"
            } else {
                return "Every day, \(timeStr) UTC"
            }
        }

        if dayOfMonth == "?" && month == "*" && dayOfWeek == "MON-FRI" {
            return "Weekdays at \(timeStr) UTC"
        }

        if dayOfMonth == "?" && month == "*" {
            if let dowDisplay = dayOfWeekDisplay(dayOfWeek) {
                return "\(dowDisplay) at \(timeStr) UTC"
            }
        }

        if month != "*", dayOfMonth != "*" && dayOfMonth != "?" {
            if let monthDisplay = monthDisplay(month) {
                return "\(monthDisplay) \(dayOfMonth) at \(timeStr) UTC"
            }
        }

        return "Cron: \(inner)"
    }

    private static func dayOfWeekDisplay(_ dow: String) -> String? {
        let names: [String: String] = [
            "MON": "Mondays", "TUE": "Tuesdays", "WED": "Wednesdays",
            "THU": "Thursdays", "FRI": "Fridays", "SAT": "Saturdays", "SUN": "Sundays",
            "MON-FRI": "Weekdays", "SAT-SUN": "Weekends",
        ]
        return names[dow.uppercased()]
    }

    private static func monthDisplay(_ month: String) -> String? {
        if let num = Int(month) {
            let names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                         "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
            guard num >= 1, num <= 12 else { return nil }
            return names[num - 1]
        }
        let map: [String: String] = [
            "JAN": "Jan", "FEB": "Feb", "MAR": "Mar", "APR": "Apr",
            "MAY": "May", "JUN": "Jun", "JUL": "Jul", "AUG": "Aug",
            "SEP": "Sep", "OCT": "Oct", "NOV": "Nov", "DEC": "Dec",
        ]
        return map[month.uppercased()]
    }

    private static func parseAt(_ expr: String) -> String? {
        // at(yyyy-MM-ddTHH:mm:ss)
        let inner = String(expr.dropFirst(3).dropLast(1)).trimmingCharacters(in: .whitespaces)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        guard let date = formatter.date(from: inner) else { return nil }

        let display = DateFormatter()
        display.dateFormat = "MMM d, yyyy 'at' HH:mm"
        display.timeZone = TimeZone(identifier: "UTC")
        return "Once on \(display.string(from: date)) UTC"
    }

    // MARK: - Next Occurrences

    static func nextOccurrences(_ expr: String, count: Int, from: Date = Date(), timezone: String? = nil) -> [Date] {
        let trimmed = expr.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("rate(") && trimmed.hasSuffix(")") {
            return nextRateOccurrences(trimmed, count: count, from: from)
        } else if trimmed.hasPrefix("cron(") && trimmed.hasSuffix(")") {
            return nextCronOccurrences(trimmed, count: count, from: from, timezone: timezone)
        } else if trimmed.hasPrefix("at(") && trimmed.hasSuffix(")") {
            return nextAtOccurrences(trimmed, from: from)
        }
        return []
    }

    private static func nextRateOccurrences(_ expr: String, count: Int, from: Date) -> [Date] {
        let inner = String(expr.dropFirst(5).dropLast(1)).trimmingCharacters(in: .whitespaces)
        let parts = inner.split(separator: " ", maxSplits: 1)
        guard parts.count == 2, let value = Int(parts[0]), value > 0 else { return [] }
        let unit = String(parts[1]).lowercased()

        let seconds: TimeInterval
        switch unit {
        case "minute", "minutes": seconds = TimeInterval(value * 60)
        case "hour", "hours": seconds = TimeInterval(value * 3600)
        case "day", "days": seconds = TimeInterval(value * 86400)
        default: return []
        }

        var dates: [Date] = []
        var current = from
        for _ in 0..<count {
            current = current.addingTimeInterval(seconds)
            dates.append(current)
        }
        return dates
    }

    private static func nextCronOccurrences(_ expr: String, count: Int, from: Date, timezone: String?) -> [Date] {
        let inner = String(expr.dropFirst(5).dropLast(1)).trimmingCharacters(in: .whitespaces)
        let fields = inner.split(separator: " ").map(String.init)
        guard fields.count == 6 else { return [] }

        let tz = timezone.flatMap { TimeZone(identifier: $0) } ?? TimeZone(identifier: "UTC")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz

        var dates: [Date] = []
        var candidate = from

        for _ in 0..<(count * 1500) {
            guard dates.count < count else { break }
            candidate = calendar.date(byAdding: .minute, value: 1, to: candidate)!

            let comps = calendar.dateComponents([.minute, .hour, .day, .month, .weekday, .year], from: candidate)
            guard let minute = comps.minute, let hour = comps.hour,
                  let day = comps.day, let month = comps.month,
                  let weekday = comps.weekday, let year = comps.year else { continue }

            if matchesCronField(fields[0], value: minute, max: 59) &&
               matchesCronField(fields[1], value: hour, max: 23) &&
               matchesCronDayOfMonth(fields[2], value: day) &&
               matchesCronMonth(fields[3], value: month) &&
               matchesCronDayOfWeek(fields[4], weekday: weekday) &&
               matchesCronYear(fields[5], value: year) {
                dates.append(candidate)
            }
        }
        return dates
    }

    private static func matchesCronField(_ field: String, value: Int, max: Int) -> Bool {
        if field == "*" { return true }
        // Comma-separated values
        let parts = field.split(separator: ",")
        for part in parts {
            let p = String(part)
            // Range
            if p.contains("-") {
                let range = p.split(separator: "-").compactMap { Int($0) }
                if range.count == 2, value >= range[0], value <= range[1] { return true }
            }
            // Slash (step)
            else if p.contains("/") {
                let stepParts = p.split(separator: "/")
                if stepParts.count == 2, let step = Int(stepParts[1]) {
                    let start = Int(stepParts[0]) ?? 0
                    if step > 0, (value - start) >= 0, (value - start) % step == 0 { return true }
                }
            }
            // Exact
            else if let exact = Int(p), exact == value { return true }
        }
        return false
    }

    private static func matchesCronDayOfMonth(_ field: String, value: Int) -> Bool {
        if field == "*" || field == "?" { return true }
        return matchesCronField(field, value: value, max: 31)
    }

    private static func matchesCronMonth(_ field: String, value: Int) -> Bool {
        if field == "*" { return true }
        let mapped = mapMonthNames(field)
        return matchesCronField(mapped, value: value, max: 12)
    }

    private static func matchesCronDayOfWeek(_ field: String, weekday: Int) -> Bool {
        if field == "*" || field == "?" { return true }
        // Convert Calendar weekday (Sun=1..Sat=7) to cron (SUN=1..SAT=7)
        let mapped = mapDayNames(field)
        return matchesCronField(mapped, value: weekday, max: 7)
    }

    private static func matchesCronYear(_ field: String, value: Int) -> Bool {
        if field == "*" { return true }
        return matchesCronField(field, value: value, max: 9999)
    }

    private static func mapMonthNames(_ field: String) -> String {
        let map = ["JAN": "1", "FEB": "2", "MAR": "3", "APR": "4", "MAY": "5", "JUN": "6",
                   "JUL": "7", "AUG": "8", "SEP": "9", "OCT": "10", "NOV": "11", "DEC": "12"]
        var result = field.uppercased()
        for (name, num) in map {
            result = result.replacingOccurrences(of: name, with: num)
        }
        return result
    }

    private static func mapDayNames(_ field: String) -> String {
        let map = ["SUN": "1", "MON": "2", "TUE": "3", "WED": "4", "THU": "5", "FRI": "6", "SAT": "7"]
        var result = field.uppercased()
        for (name, num) in map {
            result = result.replacingOccurrences(of: name, with: num)
        }
        return result
    }

    private static func nextAtOccurrences(_ expr: String, from: Date) -> [Date] {
        let inner = String(expr.dropFirst(3).dropLast(1)).trimmingCharacters(in: .whitespaces)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        guard let date = formatter.date(from: inner), date > from else { return [] }
        return [date]
    }
}
