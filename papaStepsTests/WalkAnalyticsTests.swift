import Foundation
import Testing
@testable import papaSteps

struct WalkAnalyticsTests {
    private let melbourne = TimeZone(identifier: "Australia/Melbourne")!

    @Test
    func weeklyAggregatesUseTheWalkStartTimeZoneAndExcludeWalksWithoutAUsableRoute() {
        let now = date(2026, 8, 15, 12)
        let currentWeekWalk = walk(
            start: date(2026, 8, 9, 15),
            timeZoneIdentifier: "Australia/Melbourne",
            distance: 1_200,
            steps: 1_600
        )
        let unusableRouteWalk = walk(
            start: date(2026, 8, 12, 9),
            timeZoneIdentifier: "Australia/Melbourne",
            distance: 100,
            steps: 300,
            routeQuality: .unavailable
        )
        let service = WalkAnalyticsService(timeZone: melbourne)

        let snapshot = service.makeSnapshot(
            walks: [currentWeekWalk, unusableRouteWalk],
            now: now
        )

        #expect(snapshot.currentWeek.week == WalkWeek(year: 2026, number: 33))
        #expect(snapshot.currentWeek.walkCount == 1)
        #expect(snapshot.currentWeek.totals.distanceMeters == 1_200)
        #expect(snapshot.eligibleWalkCount == 1)
        #expect(snapshot.ineligibleWalkCount == 1)
        #expect(
            WalkWeek.from(
                currentWeekWalk.startDate,
                timeZoneIdentifier: currentWeekWalk.timeZoneIdentifier
            ) != WalkWeek.from(currentWeekWalk.startDate, timeZoneIdentifier: "UTC")
        )
    }

    @Test
    func eligibilityAcceptsAnyFinishedWalkWithAUsableRouteRegardlessOfDistanceOrDuration() {
        let briefWalk = walk(
            start: date(2026, 8, 10, 9),
            timeZoneIdentifier: "Australia/Melbourne",
            distance: 200,
            movingDuration: 240
        )
        let unusableRouteWalk = walk(
            start: date(2026, 8, 10, 9),
            timeZoneIdentifier: "Australia/Melbourne",
            distance: 5_000,
            routeQuality: .unavailable
        )
        let service = WalkAnalyticsService(timeZone: melbourne)

        let snapshot = service.makeSnapshot(
            walks: [briefWalk, unusableRouteWalk],
            now: date(2026, 8, 15, 12)
        )

        #expect(snapshot.eligibleWalkCount == 1)
        #expect(snapshot.ineligibleWalkCount == 1)
        #expect(snapshot.rulesVersion == WalkEligibilityRules.current.version)
    }

    @Test
    func currentWeekComparesAgainstPreviousAndFourWeekBaseline() {
        let service = WalkAnalyticsService(timeZone: melbourne)
        let current = walk(start: date(2026, 8, 10, 9), timeZoneIdentifier: "Australia/Melbourne", distance: 2_000)
        let previous = walk(start: date(2026, 8, 3, 9), timeZoneIdentifier: "Australia/Melbourne", distance: 1_000)
        let twoWeeksAgo = walk(start: date(2026, 7, 27, 9), timeZoneIdentifier: "Australia/Melbourne", distance: 3_000)

        let snapshot = service.makeSnapshot(
            walks: [current, previous, twoWeeksAgo],
            now: date(2026, 8, 15, 12)
        )

        let previousComparison = snapshot.comparisons.first {
            $0.metric == .distance && $0.kind == .previousWeek
        }
        let averageComparison = snapshot.comparisons.first {
            $0.metric == .distance && $0.kind == .fourWeekAverage
        }
        #expect(previousComparison?.percentageChange == 1)
        #expect(averageComparison?.referenceValue == 1_000)
        #expect(snapshot.comparisons.count == WalkProgressMetric.allCases.count * 3)
        #expect(snapshot.currentStreak == 3)
    }

    @Test
    func badgesAreDerivedIdempotentlyFromEligibleSourceWalks() {
        let service = WalkAnalyticsService(timeZone: melbourne)
        let walks = (0..<5).map { offset in
            walk(
                start: date(2026, 8, 10 + offset, 9),
                timeZoneIdentifier: "Australia/Melbourne",
                distance: 2_100
            )
        }

        let first = service.makeSnapshot(walks: walks, now: date(2026, 8, 15, 12))
        let second = service.makeSnapshot(walks: walks, now: date(2026, 8, 15, 12))

        #expect(first.badges == [.firstWalk, .fiveWalks, .tenKilometres])
        #expect(second.badges == first.badges)
        #expect(first.badges.count == Set(first.badges).count)
    }

    private func walk(
        start: Date,
        timeZoneIdentifier: String,
        distance: Double,
        steps: Int = 1_000,
        movingDuration: TimeInterval = 600,
        routeQuality: RouteQuality = .good
    ) -> WalkSummary {
        WalkSummary(
            id: UUID(),
            startDate: start,
            endDate: start.addingTimeInterval(movingDuration),
            timeZoneIdentifier: timeZoneIdentifier,
            elapsedDuration: movingDuration,
            movingDuration: movingDuration,
            displayDistance: distance,
            distanceSource: .route,
            displaySteps: steps,
            stepSource: .motion,
            averageSpeed: distance / movingDuration,
            elevationGain: 20,
            routeQuality: routeQuality,
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
