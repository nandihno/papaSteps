import Testing
@testable import papaSteps

struct WalkDisplayFormattingTests {
    @Test
    func distanceAndAltitudeUseTheSelectedUnitSystem() {
        let metric = WalkDisplayConfiguration(
            distanceUnit: .metric,
            speedDisplay: .speed
        )
        let imperial = WalkDisplayConfiguration(
            distanceUnit: .imperial,
            speedDisplay: .speed
        )

        #expect(WalkMetricFormatting.distance(1_000, configuration: metric).contains("km"))
        #expect(WalkMetricFormatting.distance(1_000, configuration: imperial).contains("mi"))
        #expect(WalkMetricFormatting.altitude(100, configuration: metric).contains("m"))
        #expect(WalkMetricFormatting.altitude(100, configuration: imperial).contains("ft"))
    }

    @Test
    func paceUsesTheSelectedDistanceUnitWithoutChangingTheInputSpeed() {
        let metricPace = WalkDisplayConfiguration(
            distanceUnit: .metric,
            speedDisplay: .pace
        )
        let imperialPace = WalkDisplayConfiguration(
            distanceUnit: .imperial,
            speedDisplay: .pace
        )

        #expect(WalkMetricFormatting.speed(2, configuration: metricPace) == "8:20 min/km")
        #expect(WalkMetricFormatting.speed(2, configuration: imperialPace) == "13:25 min/mi")
    }

    @Test
    func unavailableOrInvalidSpeedRemainsUnavailableInPaceMode() {
        let configuration = WalkDisplayConfiguration(
            distanceUnit: .metric,
            speedDisplay: .pace
        )

        #expect(WalkMetricFormatting.speed(nil, configuration: configuration) == "—")
        #expect(WalkMetricFormatting.speed(0, configuration: configuration) == "—")
    }
}
