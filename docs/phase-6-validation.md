# Phase 6 validation

Date: 11 August 2026

## Implemented foundation

- Progress is calculated on demand from repository summary snapshots; it does not persist duplicate weekly totals, personal-best flags, streak state, or badge-award records.
- `WalkEligibilityRules` is a versioned domain predicate. Version 1 requires at least five minutes of moving time, 250 m of distance, and a route quality other than unavailable. Ineligible saved walks remain in History but are excluded from every Phase 6 progress calculation.
- Each eligible walk is assigned to its ISO week using the timezone captured at the walk's start. Changing the device timezone later cannot relocate historical activity.
- `WalkProgressRules` owns weekly targets and badge thresholds. The Progress view renders the domain result rather than encoding product thresholds itself.
- The Progress tab shows current-week distance, duration, steps, and elevation; a zero-baseline weekly-distance chart; all-metric comparisons with the previous week, best week, and rolling four-week baseline; personal bests; streak; goals; and derived badges.

## Automated gates

| Gate | Result | Evidence |
|---|---|---|
| Unit tests | Pass | 59 tests on iPhone 17 Pro simulator, including Phase 6 checks for stored-timezone week bucketing, ineligible exclusion, rules-version recomputation without source mutation, comparisons, streaks, and idempotent badges. |
| Progress UI smoke test | Pass | The Progress tab opens from the application tab bar and exposes the empty-state eligibility explanation in the UI-testing fixture. |
| Build integration | Pass | The app, Live Activity extension, unit-test target, and UI-test target compile successfully as part of the simulator test run. |
| Release build | Pass | Unsigned Release build for the generic iOS Simulator target succeeds, including the Live Activity extension. |

## Manual scenarios still required

| ID | Status | Expected result |
|---|---|---|
| P6-01 | Pending physical iPhone | Seed walks across multiple weeks. Weekly totals match the sum of eligible source walks. |
| P6-02 | Pending physical iPhone | Exceed a previous best week. The comparison identifies the correct dimension and percentage without overwriting history. |
| P6-03 | Pending physical iPhone | Cross a week boundary/time-zone change. Each walk remains in the ISO week determined by the timezone stored at its start, even after a later device-zone change. |
| P6-04 | Pending physical iPhone | Add or delete an old walk. Aggregates and personal bests recompute correctly when Progress is revisited. |
| P6-05 | Pending physical iPhone | Meet the same badge condition twice. It appears once and remains explainable from its eligible source data. |

## Scope boundary

Phase 6 does not write progress summaries back to SwiftData. This keeps eligibility-rule and goal/badge-rule revisions reversible: releasing a later rules version recomputes analytics from the immutable saved walk summaries rather than migrating or rewriting a user's walking history.
