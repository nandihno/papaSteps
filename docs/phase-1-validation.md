# Phase 1 validation

Date: 11 August 2026

## Automated gates

Environment: Xcode 26.6 (17F113), iPhone 17 Pro Simulator, iOS 26.5.

| Gate | Result | Evidence |
|---|---|---|
| Debug build | Pass | The complete app target builds for the generic iOS Simulator destination. |
| Release build | Pass | The whole-module optimized app builds for arm64 and x86_64 simulator architectures. |
| Physical-iPhone compile | Pass | The app builds for the generic arm64 iOS destination after making Core Motion callbacks explicitly nonisolated from the main actor. This is a compile gate, not an installed-device runtime result. |
| Unit tests | Pass | 21 Swift Testing tests cover lifecycle and retry exits, contextual permission start, duplicate prevention, deterministic metrics, invalid/stale values, circular direction, route jumps, reduced accuracy, paused pedometer offsets, reconciliation ordering, altimeter restarts, SwiftData idempotency, and cascade deletion. |
| UI tests | Pass | Three XCUITests cover launch without a permission wall, the contextual permission primer, and Start → Pause → Resume → Done → Keep Walking → Finish → saved summary. |
| Configuration/static checks | Pass | Project/plist validation, whitespace checks, strict Swift compilation, and the repository code-review checklist pass. |

## Manual scenarios

Run these on a physical iPhone using a Debug build. Record the device model, iOS version, approximate route/conditions, and observations.

| ID | Status | Expected result |
|---|---|---|
| P1-01 | Pending physical device | Walk outdoors for at least five minutes. Steps and moving time increase, and speed settles to a plausible value. |
| P1-02 | Pending physical device | Make two clear 90-degree turns. Direction follows the turns without oscillating wildly while stopped. |
| P1-03 | Pending physical device | Walk up a known hill or stair section. Elevation gain increases plausibly and never falls on descent. |
| P1-04 | Pending physical device | Stand still for 60 seconds. Elapsed time continues, moving time/speed respond appropriately, and direction becomes stale. |
| P1-05 | Pending physical device | Pause, move, then resume. Paused movement is excluded from distance/moving time and recording continues afterward. |
| P1-06 | Pending physical device | Tap Done and choose Keep Walking. The active session and cumulative metrics remain intact. |
| P1-07 | Pending physical device | Finish the walk. Exactly one local summary is created even if controls are tapped repeatedly. |

## Physical-device observations

| Date | Scenario | Observation | Resolution | Status |
|---|---|---|---|---|
| 11 August 2026 | Start Walk with Motion and Location permissions not yet determined | The first Core Motion callback stopped in `_dispatch_assert_queue_fail`. The console also reported that Core Motion could not read its protected managed-preferences plist and was falling back to public effective-user settings. | Core Motion handlers that Apple invokes on background queues are now explicitly `@Sendable`, so they do not inherit the client's `MainActor` executor. The protected-plist fallback is an Apple framework diagnostic and requires no app file access. | Pending physical-device retest with the updated build. |

Phase 1 is automated-gate complete. It is not field-validation complete until P1-01 through P1-07 have been run and the results are recorded here.
