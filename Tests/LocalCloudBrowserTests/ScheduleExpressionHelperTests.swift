import Testing
import Foundation
@testable import LocalCloudBrowser

@Suite("ScheduleExpressionHelper")
struct ScheduleExpressionHelperTests {

    // MARK: - humanReadable — rate expressions

    @Test("rate(1 minute) → Every minute")
    func rateOneMinute() {
        #expect(ScheduleExpressionHelper.humanReadable("rate(1 minute)") == "Every minute")
    }

    @Test("rate(1 hour) → Every hour")
    func rateOneHour() {
        #expect(ScheduleExpressionHelper.humanReadable("rate(1 hour)") == "Every hour")
    }

    @Test("rate(1 day) → Every day")
    func rateOneDay() {
        #expect(ScheduleExpressionHelper.humanReadable("rate(1 day)") == "Every day")
    }

    @Test("rate(5 minutes) → Every 5 minutes")
    func rateFiveMinutes() {
        #expect(ScheduleExpressionHelper.humanReadable("rate(5 minutes)") == "Every 5 minutes")
    }

    @Test("rate(2 hours) → Every 2 hours")
    func rateTwoHours() {
        #expect(ScheduleExpressionHelper.humanReadable("rate(2 hours)") == "Every 2 hours")
    }

    @Test("rate(7 days) → Every 7 days")
    func rateSevenDays() {
        #expect(ScheduleExpressionHelper.humanReadable("rate(7 days)") == "Every 7 days")
    }

    // MARK: - humanReadable — cron expressions

    @Test("daily cron → Every day at HH:MM UTC")
    func cronDaily() {
        let result = ScheduleExpressionHelper.humanReadable("cron(30 10 * * ? *)")
        #expect(result == "Every day at 10:30 UTC")
    }

    @Test("weekday cron → Weekdays at HH:MM UTC")
    func cronWeekdays() {
        let result = ScheduleExpressionHelper.humanReadable("cron(0 9 ? * MON-FRI *)")
        #expect(result == "Weekdays at 09:00 UTC")
    }

    @Test("specific day cron → Mondays at HH:MM UTC")
    func cronSpecificDay() {
        let result = ScheduleExpressionHelper.humanReadable("cron(0 12 ? * MON *)")
        #expect(result == "Mondays at 12:00 UTC")
    }

    @Test("specific month cron")
    func cronSpecificMonth() {
        let result = ScheduleExpressionHelper.humanReadable("cron(0 0 15 1 ? *)")
        #expect(result == "Jan 15 at 00:00 UTC")
    }

    @Test("every minute cron")
    func cronEveryMinute() {
        let result = ScheduleExpressionHelper.humanReadable("cron(* * * * ? *)")
        #expect(result?.contains("every minute") == true)
    }

    // MARK: - humanReadable — at expressions

    @Test("at expression → Once on date UTC")
    func atExpression() {
        let result = ScheduleExpressionHelper.humanReadable("at(2024-06-15T14:30:00)")
        #expect(result != nil)
        #expect(result!.contains("Once on"))
        #expect(result!.contains("UTC"))
    }

    // MARK: - humanReadable — unknown

    @Test("returns nil for unknown expressions")
    func unknownExpression() {
        #expect(ScheduleExpressionHelper.humanReadable("something else") == nil)
    }

    // MARK: - nextOccurrences — rate

    @Test("nextOccurrences for rate expression")
    func nextRateOccurrences() {
        let from = Date(timeIntervalSince1970: 1700000000)
        let dates = ScheduleExpressionHelper.nextOccurrences("rate(5 minutes)", count: 3, from: from)
        #expect(dates.count == 3)
        #expect(dates[0].timeIntervalSince(from) == 300)
        #expect(dates[1].timeIntervalSince(from) == 600)
        #expect(dates[2].timeIntervalSince(from) == 900)
    }

    @Test("nextOccurrences for rate(1 hour)")
    func nextRateHourOccurrences() {
        let from = Date(timeIntervalSince1970: 1700000000)
        let dates = ScheduleExpressionHelper.nextOccurrences("rate(1 hour)", count: 2, from: from)
        #expect(dates.count == 2)
        #expect(dates[0].timeIntervalSince(from) == 3600)
    }

    // MARK: - nextOccurrences — at

    @Test("nextOccurrences for future at expression returns 1 date")
    func nextAtOccurrencesFuture() {
        let dates = ScheduleExpressionHelper.nextOccurrences(
            "at(2099-01-01T00:00:00)",
            count: 5,
            from: Date()
        )
        #expect(dates.count == 1)
    }

    @Test("nextOccurrences for past at expression returns empty")
    func nextAtOccurrencesPast() {
        let dates = ScheduleExpressionHelper.nextOccurrences(
            "at(2020-01-01T00:00:00)",
            count: 5,
            from: Date()
        )
        #expect(dates.isEmpty)
    }

    // MARK: - nextOccurrences — unknown

    @Test("nextOccurrences returns empty for unknown expression")
    func nextUnknownOccurrences() {
        let dates = ScheduleExpressionHelper.nextOccurrences("invalid", count: 3)
        #expect(dates.isEmpty)
    }
}
