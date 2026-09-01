import Foundation
import Testing
@testable import papaSteps

struct HistoryViewTests {
    @Test
    func groupBucketsWalksByISOWeekAndPreservesFirstSeenOrder() {
        // A Monday and the following Sunday belong to the same ISO week; the
        // next Monday starts a new one.
        let mondayWalk = walk(start: date(2026, 8, 10, 9))
        let sundayWalk = walk(start: date(2026, 8, 16, 18))
        let nextWeekWalk = walk(start: date(2026, 8, 17, 7))

        let weeks = WalkHistoryWeek.group([nextWeekWalk, mondayWalk, sundayWalk])

        #expect(weeks.map(\.id) == [
            WalkWeek.from(nextWeekWalk.startDate, timeZoneIdentifier: "UTC").id,
            WalkWeek.from(mondayWalk.startDate, timeZoneIdentifier: "UTC").id,
        ])
        #expect(weeks[1].walks.map(\.id) == [mondayWalk.id, sundayWalk.id])
        #expect(weeks[1].totalDistance == mondayWalk.displayDistance! + sundayWalk.displayDistance!)
    }

    @Test
    func titleLabelsTheCurrentAndPreviousWeekRelatively() {
        let now = date(2026, 8, 13, 12)
        let currentWeek = WalkWeek.current(at: now, timeZone: .current)
        let previousWeek = currentWeek.previous(in: .current)

        let current = WalkHistoryWeek(id: currentWeek.id, week: currentWeek, walks: [])
        let previous = WalkHistoryWeek(id: previousWeek.id, week: previousWeek, walks: [])

        #expect(current.title(now: now) == "This week")
        #expect(previous.title(now: now) == "Last week")
    }

    @Test
    func titleFormatsOlderWeeksAsADateRangeAndOnlyShowsTheYearWhenItDiffers() {
        let now = date(2026, 8, 13, 12)
        let sameYearWeek = WalkWeek.from(date(2026, 1, 5, 9), timeZoneIdentifier: TimeZone.current.identifier)
        let priorYearWeek = WalkWeek.from(date(2025, 8, 11, 9), timeZoneIdentifier: TimeZone.current.identifier)

        let sameYear = WalkHistoryWeek(id: sameYearWeek.id, week: sameYearWeek, walks: [])
        let priorYear = WalkHistoryWeek(id: priorYearWeek.id, week: priorYearWeek, walks: [])

        #expect(!sameYear.title(now: now).contains("2026"))
        #expect(priorYear.title(now: now).contains("2025"))
    }

    private func walk(start: Date, distance: Double = 500) -> WalkSummary {
        let movingDuration: TimeInterval = 600
        return WalkSummary(
            id: UUID(),
            startDate: start,
            endDate: start.addingTimeInterval(movingDuration),
            timeZoneIdentifier: "UTC",
            elapsedDuration: movingDuration,
            movingDuration: movingDuration,
            displayDistance: distance,
            distanceSource: .route,
            displaySteps: 800,
            stepSource: .motion,
            averageSpeed: distance / movingDuration,
            elevationGain: 10,
            routeQuality: .good,
            routeQualityReason: nil,
            healthEnrichmentStatus: .notRequested,
            origin: .papaSteps,
            healthSourceName: nil
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour
        ))!
    }
}
