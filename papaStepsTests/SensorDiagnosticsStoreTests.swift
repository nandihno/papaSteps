import Testing
@testable import papaSteps

@MainActor
struct SensorDiagnosticsStoreTests {
    @Test
    func reducedAccuracyIsDistinctAndCanBecomeFullUsingFakes() async {
        let location = FakeLocationCapabilityClient(
            snapshot: LocationCapabilitySnapshot(
                authorization: .whenInUse,
                accuracy: .reduced,
                latestFix: nil
            )
        )
        let store = SensorDiagnosticsStore(
            motionClient: FakeMotionCapabilityClient(),
            locationClient: location,
            healthClient: FakeHealthCapabilityClient()
        )

        await store.refresh()

        #expect(store.locationAccuracy == .reduced)
        #expect(
            store.snapshot.location.first(where: { $0.id == "location.accuracy" })?.availability == .limited
        )

        await store.requestTemporaryFullAccuracy()

        #expect(store.locationAccuracy == .full)
        #expect(
            store.snapshot.location.first(where: { $0.id == "location.accuracy" })?.availability == .available
        )
    }
}
