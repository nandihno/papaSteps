# Phase 4 validation

Date: 11 August 2026

## Automated gates

Environment: Xcode 26.6 (17F113), iPhone 17 Pro Simulator, iOS 26.5 SDK.

| Gate | Result | Evidence |
|---|---|---|
| Debug build and unit tests | Pass | 51 Swift Testing tests pass. Phase 4 coverage includes corroborated stationary-window detection, short-stop and low-confidence suppression, movement cancellation, Keep Walking suppression, duplicate-stream prevention during reconciliation, one notification per candidate, Lock Screen action idempotency, and interrupted Live Activity recovery. |
| UI regression tests | Pass | Six XCUITests pass, covering launch, contextual permissions, the local walk lifecycle, interrupted-draft recovery, Apple Health settings, and manual Health workout import. |
| Release physical-iPhone compile | Pass | The optimized app and Live Activity extension build for generic arm64 iOS with signing disabled. Xcode validates the embedded `papaStepsLiveActivity.appex` binary. This proves SDK and target integration, not physical-device runtime behavior. |
| App configuration | Pass | The app plist, widget plist, and Xcode project lint successfully. The built app declares the location background mode and Live Activity support, and contains the WidgetKit extension. |
| Background lifecycle | Pass | An active location stream owns one `CLBackgroundActivitySession`; foreground reconciliation queries authoritative pedometer history without restarting sensor streams; app backgrounding and periodic intervals persist checkpoints. Existing paused-step offsets and altimeter restart monotonicity remain covered. |
| Live Activity actions | Pass | Pause, Resume, Finish, and Keep Walking intents route through the same idempotent `WalkSessionStore` state machine as in-app controls. A recovered draft marks a surviving activity as interrupted rather than leaving stale active controls. |
| Finish prompting | Pass | Thresholds live in `TrackingConfiguration`. The detector requires at least two available stationary signals for the full configured window, emits one candidate, cancels on renewed movement, and suppresses immediate repeats after Keep Walking. Notifications are optional and requested only from Walk Recording settings; the in-app confirmation remains available without notification permission. |
| Final code review | Pass | Background-session lifetime, sensor cleanup, ActivityKit lifecycle, notification cleanup, recovery behavior, strict-concurrency boundaries, and downstream Health/persistence flows were reviewed. No unresolved correctness or security finding remains. |

`BGTaskScheduler` is deliberately not used for active recording. Scheduled background tasks run at system-selected times and cannot maintain a continuous walk. The live path is instead tied to the user-started Core Location background activity, with persisted checkpoints and foreground pedometer reconciliation as the recovery boundary.

Initial field-test values are a three-minute minimum walk duration, a three-minute corroborated stationary window, and a five-minute suppression interval after Keep Walking. These remain tuning values rather than UI constants.

## Manual scenarios

Run these on a physical iPhone using a signed Debug build. Before P4-02, enable **Walk Recording → Notify me when a walk may be finished** and permit notifications. Record the iPhone model, iOS version, approximate duration, permission state, and observed steps/distance/ascent before and after locking.

| ID | Status | Expected result |
|---|---|---|
| P4-01 | Pending physical device | Start, lock the phone, walk for 10 minutes, and unlock. One session remains active; route and metrics cover the locked period; pedometer backfill is neither frozen nor double-counted. |
| P4-01b | Pending physical device | Repeat lock, walk, and unlock twice in one walk. Every foreground reconciliation runs once without restarting streams; steps and ascent remain monotonic. |
| P4-02 | Pending physical device | After a walk longer than three minutes, remain stopped for the three-minute stationary window. One finish prompt appears; a backgrounded app also delivers one actionable notification when reminders are enabled. |
| P4-03 | Pending physical device | Choose Keep Walking and resume movement. The prompt and notification dismiss, recording continues, and another prompt cannot appear during the five-minute suppression interval. |
| P4-04 | Pending physical device | Pause briefly at traffic lights or stop for less than the threshold. No walk is completed and ordinary movement continues normally. |
| P4-05 | Pending physical device | Pause/resume, then finish from the Lock Screen. The action finalizes exactly one local walk and opens the correct completed state on foreground; Health export remains subject to its existing preference. |
| P4-06 | Pending physical device | Force-terminate during a walk and relaunch. The surviving Live Activity says Needs attention, and the app reports the checkpoint gap with explicit resume, finish, or discard choices without inventing route points. |

## Evidence boundary

Phase 4 is automated-gate complete. Simulator tests prove deterministic detector behavior, state-machine routing, notification decisions, recovery decisions, and regression safety. The unsigned generic-device Release build proves the Core Location, Core Motion, ActivityKit, App Intents, UserNotifications, and widget APIs compile and embed correctly. Only the physical-device scenarios above can prove locked-screen execution time, real sensor delivery/backfill, Live Activity presentation and actions, local notification delivery, and force-termination recovery under iOS process scheduling.
