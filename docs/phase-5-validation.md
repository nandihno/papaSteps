# Phase 5 validation

Date: 11 August 2026

## Implemented foundation

- A persisted display preference controls metric/imperial distance and elevation, plus speed/pace presentation. Stored walk records remain in metres and metres per second, so changing a preference never migrates or rewrites history.
- The same formatting configuration is injected into live metrics, completed summaries, History, walk detail, and Health workout import rows.
- Metric cards expose a stable VoiceOver name, value, availability detail, and stale-metric hint. Metric grids collapse to one column at accessibility Dynamic Type sizes.
- Privacy & Data documents the beta data boundary and provides an explicit, confirmation-gated delete-all action. It deletes local completed walks, recoverable drafts, and cascade-owned route points, but never deletes a separately saved Apple Health workout.

## Automated gates

| Gate | Result | Evidence |
|---|---|---|
| Unit tests | Pass | 55 tests cover existing lifecycle, Health, route, and persistence paths plus metric/imperial conversion, speed/pace conversion, unavailable pace, and delete-all cascade behavior. |
| Release build | Pass | Unsigned Release build for the generic iOS Simulator target succeeds, including the Live Activity extension. |
| Sensitive log review | Pass for current app logs | The only production `Logger` calls record export stage and error domain/code; no route coordinate, Health value, or sample payload is logged. |

## Manual scenarios still required

| ID | Status | Expected result |
|---|---|---|
| P5-01 | Pending physical iPhone | At the largest accessibility text size, metric cards become single-column rows; their values and Pause/Done controls remain readable and reachable. |
| P5-02 | Pending physical iPhone | With VoiceOver enabled, each live card announces its name, value/unit, and live, acquiring, stale, or unavailable state. |
| P5-03 | Pending physical iPhone | Change Walk Recording → Display between metric/imperial and speed/pace. Current and historical views update immediately; returning to the prior option restores only presentation, not stored values. |
| P5-04 | Pending physical iPhone | Record a 60–90 minute walk while observing battery, thermal state, memory, route-point count, and post-walk database save time. Agree budget thresholds before calling this gate complete. |
| P5-05 | Pending physical iPhone | Traverse a poor-location area. The reduced/degraded explanation remains truthful and Motion-based metrics continue. |
| P5-06 | Pending physical iPhone | With both local walks and an exported Apple Health workout present, use Privacy & Data → Delete All Local Walk Data. History and a recoverable draft clear; the Apple Health workout remains. |

## Beta readiness boundary

Before TestFlight, record the iPhone models and iOS versions used for P5-01 through P5-05, establish long-walk memory/battery/database budgets from those runs, and complete App Store Connect privacy answers from the actual release build. This repository does not yet automate thermal or battery profiling, and no claim is made that those physical-device gates have passed.
