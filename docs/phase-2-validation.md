# Phase 2 validation

Date: 11 August 2026

## Automated gates

Environment: Xcode 26.6 (17F113), iPhone 17 Pro Simulator, iOS 26.5.

| Gate | Result | Evidence |
|---|---|---|
| Debug build | Pass | The complete app and test targets compile for the iPhone 17 Pro Simulator. |
| Release build | Pass | The optimized app builds for the generic iOS Simulator destination. |
| Physical-iPhone compile | Pass | The app builds for the generic arm64 iOS destination with signing disabled. This validates device-framework compilation, not outdoor sensor behavior. |
| Unit tests | Pass | 27 Swift Testing tests pass. Phase 2 coverage includes the one-kilometre GPX tolerance, impossible-jump rejection, pause-safe route segmentation, reduced accuracy, checkpoint recovery, History exclusion of drafts, completion in place, idempotency, deferred detail points, cascade deletion, and an on-disk SwiftData V1-to-V2 migration. |
| UI tests | Pass | Four XCUITests cover launch, contextual permissions, the complete manual walk lifecycle through History/detail/map, and explicit choices for an interrupted draft. |
| Persistence migration | Pass | A real V1 store opens through `PapaStepsMigrationPlan`, retains its walk, and receives the optional Phase 2 metadata without data loss. |

## Manual scenarios

Run these on a physical iPhone using a Debug build. Record the device model, iOS version, route or signal conditions, permission state, and observations.

| ID | Status | Expected result |
|---|---|---|
| P2-01 | Pending physical device | Complete a known 1–2 km route. Summary distance is plausible and the map follows the path without a large teleport. |
| P2-02 | Pending physical device | Walk where GPS briefly degrades. Route quality is degraded if needed and no impossible spike is drawn. |
| P2-03 | Pending physical device | Relaunch after a completed walk. It appears once in History with unchanged stats and route. |
| P2-04 | Pending physical device | Start a walk, background briefly, and relaunch. The app offers Resume, Finish at Last Checkpoint, and Discard without auto-completing the draft. |
| P2-05 | Pending physical device | Delete a historical walk and confirm. It remains absent after relaunch and its track points are removed. |
| P2-06 | Pending physical device | Turn Precise Location off and decline full accuracy. No route, GPS speed, or polyline appears; non-location metrics continue and the limitation is explained. |
| P2-07 | Pending physical device | Revoke Location in Settings mid-walk. The route freezes at the last accepted point, other available metrics continue, and relaunch names the permission change. |

## Evidence boundary

Phase 2 is automated-gate complete. Simulator tests validate deterministic tracking, persistence, migration, navigation, and recovery behavior. The generic-device build validates compilation against the physical-iOS SDK. None of those replace the seven outdoor, permission-transition, relaunch, and deletion scenarios above, so Phase 3 should wait until those results are accepted on a physical iPhone.
