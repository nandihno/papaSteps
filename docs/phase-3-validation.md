# Phase 3 validation

Date: 11 August 2026

## Automated gates

Environment: Xcode 26.6 (17F113), iPhone 17e Simulator, iOS 26.5.

| Gate | Result | Evidence |
|---|---|---|
| Debug build | Pass | The complete app and test targets compile for the iOS Simulator SDK. |
| Release build | Pass | The optimized app builds for the generic iOS Simulator destination. |
| Physical-iPhone compile | Pass | The app builds for the generic arm64 iOS destination with signing disabled, including the live HealthKit query and workout APIs. This is an SDK compile gate, not a Health/Fitness runtime result. |
| Unit tests | Pass | 41 Swift Testing tests pass. Phase 3 coverage includes empty and malformed Health results, delayed enrichment of the same local walk, single-source selection for overlapping iPhone/Watch data, preservation of authoritative local metrics, metadata-correlated workout retry, denied workout-write permission recovery, HealthKit workout-payload contract validation, SwiftData container lifetime, and direct V2-to-V3 plus V1-through-V3 migrations. |
| UI tests | Pass | Five XCUITests cover launch, contextual Motion/Location permissions, the full local walk lifecycle, interrupted-draft recovery, the optional Apple Health access flow, and neutral Health guidance on a completed walk. |
| Health source filtering | Pass | The live client discovers HealthKit sources and issues each quantity-sample query with an explicit source predicate. The pure reconciliation layer then selects one source/device provenance and never sums overlapping sources. |
| Workout idempotency | Pass | Before writing, the live client queries workouts by the local walk UUID stored in HealthKit metadata. The fake termination-window test proves a retry adopts the matching workout UUID and does not create another workout. |
| Persistence migration | Pass | Real on-disk V1 and V2 stores open through `PapaStepsMigrationPlan`, retain existing walk and Phase 2 metadata, and receive optional Phase 3 provenance/export fields without data loss. |
| Code review and configuration | Pass | HealthKit privacy behavior, retry paths, persistence ownership, canonical-source presentation, accessibility identifiers, entitlements, and usage descriptions were reviewed. Plist and entitlement lint passes. |

The simulator emitted an Apple runtime warning about duplicate WebCore/WebKit accessibility loader classes during UI tests. All five tests completed successfully; the warning does not reference papaSteps code.

The `HKErrorInvalidArgument` correction compiled as part of the successful 41-test Debug run. Post-correction Release-simulator and generic-device rebuilds were also attempted, but the sandbox lost access to `CoreSimulatorService` and `actool` stopped at asset-catalog compilation with “No available simulator runtimes”; neither attempt emitted a Swift compiler diagnostic. The Release and physical-iPhone compile passes in the table are the earlier Phase 3 gates, while a new on-device runtime check remains mandatory for this correction.

## Manual scenarios

Run these on a physical iPhone using a Debug build. For Health data scenarios, record the iPhone model/iOS version, Apple Watch or sensor model if applicable, Health permission selections, approximate walk duration, and the values observed in papaSteps and Health/Fitness.

| ID | Status | Expected result |
|---|---|---|
| P3-01 | Pending physical device | Decline Health access and finish a walk. Core recording remains normal and Health insights use a neutral unavailable explanation. |
| P3-02 | Pending physical device | Permit Health with Apple Watch or other heart-rate data present. Average heart rate appears with sample count, coverage, and source. |
| P3-03 | Pending physical device | Finish without eligible walking-asymmetry data. The card says Not Available rather than `0%`. |
| P3-04 | Pending physical device | Carry the iPhone near the waist on a steady flat walk and refresh later. Delayed asymmetry updates the same walk when available; otherwise the unavailable state remains honest. |
| P3-05 | Pending physical device | Enable Save new walks to Apple Health and finish. Exactly one outdoor walking workout appears in Health/Fitness with plausible time, distance, and accepted route. |
| P3-06 | Pending physical device | Retry Health enrichment/workout export for the same completed walk. No duplicate local walk or Health workout appears. |
| P3-07 | Pending physical device | Complete a walk while wearing an Apple Watch. Health step/distance provenance names one source and the values remain close to local totals rather than roughly doubling. |

## Physical-device observations

| Date | Scenario | Observation | Resolution | Status |
|---|---|---|---|---|
| 11 August 2026 | P3-05 — Save new walks to Apple Health | Health insights refreshed, but the completed walk showed “Apple Health workout export needs a retry.” The console also printed a RunningBoard `com.apple.runningboard.process-state` diagnostic. | The RunningBoard line is emitted in unrelated system UI flows and is not a HealthKit capability to add. The actual export path wrote a `distanceWalkingRunning` sample without requesting distance write access and directly instantiated `HKWorkoutRouteBuilder`. The app now requests and validates Workout, Walking + Running Distance, and Workout Route share permission; obtains the route builder from `HKWorkoutBuilder.seriesBuilder(for:)`; turns the toggle off when sharing is denied; and records/logs the real HealthKit error domain and code. | Fix automated; pending physical-device retest. |
| 11 August 2026 | P3-05 retest — 60 m / 81-step walk | HealthKit returned `com.apple.healthkit` code 3 (`HKErrorInvalidArgument`) after write permissions had been re-requested. | The installed Apple SDK exposed two invalid builder arguments: the distance sample started at the exact workout-builder start despite the API requiring a later sample start, and the builder-owned route was manually finished after `finishWorkout()`. The distance sample now starts 1 ms into the valid interval; `finishWorkout()` exclusively owns route finalization; route points are bounded, finite, ordered, and deduplicated; and future native failures retain their exact export stage. | Fix automated; pending physical-device retest. |

## Evidence boundary

Phase 3 is automated-gate complete. Simulator tests prove the deterministic processing, persistence, migration, retry, and UI states. The generic-device build proves that the live HealthKit APIs compile for iPhone. Only the physical-device scenarios above can validate real authorization choices, delayed Watch synchronization, walking-asymmetry availability, Health/Fitness workout visibility, and route association.
