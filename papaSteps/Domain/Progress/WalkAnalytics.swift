import Foundation

struct WalkEligibilityRules: Equatable, Sendable {
    static let current = WalkEligibilityRules(
        version: 1,
        minimumMovingDuration: 5 * 60,
        minimumDistanceMeters: 250
    )

    let version: Int
    let minimumMovingDuration: TimeInterval
    let minimumDistanceMeters: Double

    func isEligible(_ walk: WalkSummary) -> Bool {
        guard walk.endDate != nil,
              walk.movingDuration >= minimumMovingDuration,
              let distance = walk.displayDistance,
              distance >= minimumDistanceMeters,
              walk.routeQuality != .unavailable else {
            return false
        }
        return true
    }
}

struct WalkProgressRules: Equatable, Sendable {
    static let current = WalkProgressRules(
        version: 1,
        weeklyDistanceGoalMeters: 5_000,
        weeklyStepGoal: 7_000,
        fiveWalkBadgeCount: 5,
        tenKilometreBadgeDistanceMeters: 10_000
    )

    let version: Int
    let weeklyDistanceGoalMeters: Double
    let weeklyStepGoal: Int
    let fiveWalkBadgeCount: Int
    let tenKilometreBadgeDistanceMeters: Double
}

struct WalkWeek: Hashable, Comparable, Identifiable, Sendable {
    let year: Int
    let number: Int

    var id: String { "\(year)-\(number)" }

    static func < (lhs: WalkWeek, rhs: WalkWeek) -> Bool {
        lhs.year == rhs.year ? lhs.number < rhs.number : lhs.year < rhs.year
    }

    static func from(_ date: Date, timeZoneIdentifier: String) -> WalkWeek {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return WalkWeek(
            year: components.yearForWeekOfYear ?? 0,
            number: components.weekOfYear ?? 0
        )
    }

    static func current(at date: Date, timeZone: TimeZone) -> WalkWeek {
        from(date, timeZoneIdentifier: timeZone.identifier)
    }

    func date(in timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(
            weekday: 2,
            weekOfYear: number,
            yearForWeekOfYear: year
        )) ?? .distantPast
    }

    func previous(in timeZone: TimeZone) -> WalkWeek {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = timeZone
        let previousDate = calendar.date(byAdding: .weekOfYear, value: -1, to: date(in: timeZone))
            ?? .distantPast
        return Self.current(at: previousDate, timeZone: timeZone)
    }
}

struct WalkTotals: Equatable, Sendable {
    var distanceMeters: Double = 0
    var movingDuration: TimeInterval = 0
    var steps: Int = 0
    var elevationGain: Double = 0

    static let zero = WalkTotals()

    mutating func add(_ walk: WalkSummary) {
        distanceMeters += walk.displayDistance ?? 0
        movingDuration += walk.movingDuration
        steps += walk.displaySteps ?? 0
        elevationGain += walk.elevationGain ?? 0
    }

    static func + (lhs: WalkTotals, rhs: WalkTotals) -> WalkTotals {
        WalkTotals(
            distanceMeters: lhs.distanceMeters + rhs.distanceMeters,
            movingDuration: lhs.movingDuration + rhs.movingDuration,
            steps: lhs.steps + rhs.steps,
            elevationGain: lhs.elevationGain + rhs.elevationGain
        )
    }

    func divided(by divisor: Int) -> WalkTotals {
        guard divisor > 0 else { return .zero }
        return WalkTotals(
            distanceMeters: distanceMeters / Double(divisor),
            movingDuration: movingDuration / Double(divisor),
            steps: steps / divisor,
            elevationGain: elevationGain / Double(divisor)
        )
    }
}

struct WeeklyWalkAggregate: Identifiable, Equatable, Sendable {
    let week: WalkWeek
    let totals: WalkTotals
    let walkCount: Int

    var id: WalkWeek { week }
}

enum WalkProgressMetric: String, CaseIterable, Identifiable, Sendable {
    case distance
    case duration
    case steps
    case elevation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .distance: "Distance"
        case .duration: "Moving time"
        case .steps: "Steps"
        case .elevation: "Elevation gain"
        }
    }

    func value(in totals: WalkTotals) -> Double {
        switch self {
        case .distance: totals.distanceMeters
        case .duration: totals.movingDuration
        case .steps: Double(totals.steps)
        case .elevation: totals.elevationGain
        }
    }
}

struct PersonalBest: Identifiable, Equatable, Sendable {
    let metric: WalkProgressMetric
    let walk: WalkSummary

    var id: WalkProgressMetric { metric }
}

enum ProgressComparisonKind: String, CaseIterable, Identifiable, Sendable {
    case bestWeek
    case previousWeek
    case fourWeekAverage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bestWeek: "Best week"
        case .previousWeek: "Previous week"
        case .fourWeekAverage: "4-week average"
        }
    }
}

struct ProgressComparison: Identifiable, Equatable, Sendable {
    let metric: WalkProgressMetric
    let kind: ProgressComparisonKind
    let referenceValue: Double?
    let percentageChange: Double?

    var id: String { "\(metric.rawValue)-\(kind.rawValue)" }
}

enum ProgressBadge: String, CaseIterable, Hashable, Identifiable, Sendable {
    case firstWalk
    case fiveWalks
    case tenKilometres

    var id: String { rawValue }

    var title: String {
        switch self {
        case .firstWalk: "First Steps"
        case .fiveWalks: "Five Walks"
        case .tenKilometres: "10 km Club"
        }
    }

    var detail: String {
        switch self {
        case .firstWalk: "Complete one eligible walk"
        case .fiveWalks: "Complete five eligible walks"
        case .tenKilometres: "Walk 10 km across eligible walks"
        }
    }
}

struct ProgressGoal: Identifiable, Equatable, Sendable {
    let metric: WalkProgressMetric
    let target: Double
    let current: Double

    var id: WalkProgressMetric { metric }
    var fractionComplete: Double {
        guard target > 0 else { return 0 }
        return min(1, current / target)
    }
    var isCompleted: Bool { current >= target }
}

struct WalkAnalyticsSnapshot: Equatable, Sendable {
    let rulesVersion: Int
    let currentWeek: WeeklyWalkAggregate
    let weeklyAggregates: [WeeklyWalkAggregate]
    let eligibleWalkCount: Int
    let ineligibleWalkCount: Int
    let personalBests: [PersonalBest]
    let comparisons: [ProgressComparison]
    let goals: [ProgressGoal]
    let currentStreak: Int
    let badges: [ProgressBadge]

    static let empty = WalkAnalyticsSnapshot(
        rulesVersion: WalkEligibilityRules.current.version,
        currentWeek: WeeklyWalkAggregate(
            week: .current(at: .now, timeZone: .current),
            totals: .zero,
            walkCount: 0
        ),
        weeklyAggregates: [],
        eligibleWalkCount: 0,
        ineligibleWalkCount: 0,
        personalBests: [],
        comparisons: [],
        goals: [],
        currentStreak: 0,
        badges: []
    )
}

struct WalkAnalyticsService: Sendable {
    let rules: WalkEligibilityRules
    let progressRules: WalkProgressRules
    let timeZone: TimeZone

    init(
        rules: WalkEligibilityRules = .current,
        progressRules: WalkProgressRules = .current,
        timeZone: TimeZone = .current
    ) {
        self.rules = rules
        self.progressRules = progressRules
        self.timeZone = timeZone
    }

    func makeSnapshot(
        walks: [WalkSummary],
        now: Date = .now
    ) -> WalkAnalyticsSnapshot {
        let eligible = walks.filter(rules.isEligible)
        let currentWeek = WalkWeek.current(at: now, timeZone: timeZone)
        var totalsByWeek: [WalkWeek: WalkTotals] = [:]
        var countByWeek: [WalkWeek: Int] = [:]

        for walk in eligible {
            let week = WalkWeek.from(walk.startDate, timeZoneIdentifier: walk.timeZoneIdentifier)
            totalsByWeek[week, default: .zero].add(walk)
            countByWeek[week, default: 0] += 1
        }

        let weeklyAggregates = totalsByWeek.keys.sorted(by: >).map { week in
            WeeklyWalkAggregate(
                week: week,
                totals: totalsByWeek[week] ?? .zero,
                walkCount: countByWeek[week] ?? 0
            )
        }
        let current = WeeklyWalkAggregate(
            week: currentWeek,
            totals: totalsByWeek[currentWeek] ?? .zero,
            walkCount: countByWeek[currentWeek] ?? 0
        )

        return WalkAnalyticsSnapshot(
            rulesVersion: rules.version,
            currentWeek: current,
            weeklyAggregates: weeklyAggregates,
            eligibleWalkCount: eligible.count,
            ineligibleWalkCount: walks.count - eligible.count,
            personalBests: personalBests(from: eligible),
            comparisons: comparisons(
                current: current,
                weekly: weeklyAggregates,
                currentWeek: currentWeek
            ),
            goals: goals(for: current.totals),
            currentStreak: streak(
                from: countByWeek,
                currentWeek: currentWeek
            ),
            badges: badges(for: eligible)
        )
    }

    private func personalBests(from walks: [WalkSummary]) -> [PersonalBest] {
        WalkProgressMetric.allCases.compactMap { metric in
            guard let walk = walks.max(by: {
                metric.value(in: totals(for: $0)) < metric.value(in: totals(for: $1))
            }), metric.value(in: totals(for: walk)) > 0 else {
                return nil
            }
            return PersonalBest(metric: metric, walk: walk)
        }
    }

    private func comparisons(
        current: WeeklyWalkAggregate,
        weekly: [WeeklyWalkAggregate],
        currentWeek: WalkWeek
    ) -> [ProgressComparison] {
        let previousWeek = currentWeek.previous(in: timeZone)
        return WalkProgressMetric.allCases.flatMap { metric in
            let best = weekly.map { metric.value(in: $0.totals) }.max()
            let previous = weekly.first(where: { $0.week == previousWeek })
                .map { metric.value(in: $0.totals) }
            let rollingAverage = rollingAverage(
                for: metric,
                weekly: weekly,
                endingBefore: previousWeek
            )
            let currentValue = metric.value(in: current.totals)

            return [
                comparison(metric, .bestWeek, current: currentValue, reference: best),
                comparison(metric, .previousWeek, current: currentValue, reference: previous),
                comparison(metric, .fourWeekAverage, current: currentValue, reference: rollingAverage)
            ]
        }
    }

    private func comparison(
        _ metric: WalkProgressMetric,
        _ kind: ProgressComparisonKind,
        current: Double,
        reference: Double?
    ) -> ProgressComparison {
        guard let reference, reference > 0 else {
            return ProgressComparison(
                metric: metric,
                kind: kind,
                referenceValue: nil,
                percentageChange: nil
            )
        }
        return ProgressComparison(
            metric: metric,
            kind: kind,
            referenceValue: reference,
            percentageChange: (current - reference) / reference
        )
    }

    private func rollingAverage(
        for metric: WalkProgressMetric,
        weekly: [WeeklyWalkAggregate],
        endingBefore week: WalkWeek
    ) -> Double? {
        guard !weekly.isEmpty else { return nil }
        var total = 0.0
        var rollingWeek = week
        for _ in 0..<4 {
            if let aggregate = weekly.first(where: { $0.week == rollingWeek }) {
                total += metric.value(in: aggregate.totals)
            }
            rollingWeek = rollingWeek.previous(in: timeZone)
        }
        return total / 4
    }

    private func goals(for totals: WalkTotals) -> [ProgressGoal] {
        [
            ProgressGoal(
                metric: .distance,
                target: progressRules.weeklyDistanceGoalMeters,
                current: totals.distanceMeters
            ),
            ProgressGoal(
                metric: .steps,
                target: Double(progressRules.weeklyStepGoal),
                current: Double(totals.steps)
            )
        ]
    }

    private func streak(
        from countByWeek: [WalkWeek: Int],
        currentWeek: WalkWeek
    ) -> Int {
        var streak = 0
        var week = currentWeek
        while countByWeek[week, default: 0] > 0 {
            streak += 1
            week = week.previous(in: timeZone)
        }
        return streak
    }

    private func badges(for walks: [WalkSummary]) -> [ProgressBadge] {
        var badges: [ProgressBadge] = []
        if !walks.isEmpty { badges.append(.firstWalk) }
        if walks.count >= progressRules.fiveWalkBadgeCount { badges.append(.fiveWalks) }
        if walks.reduce(0, { $0 + ($1.displayDistance ?? 0) })
            >= progressRules.tenKilometreBadgeDistanceMeters {
            badges.append(.tenKilometres)
        }
        return badges
    }

    private func totals(for walk: WalkSummary) -> WalkTotals {
        WalkTotals(
            distanceMeters: walk.displayDistance ?? 0,
            movingDuration: walk.movingDuration,
            steps: walk.displaySteps ?? 0,
            elevationGain: walk.elevationGain ?? 0
        )
    }
}
