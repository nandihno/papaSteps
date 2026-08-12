# papaSteps — Product and Technical Specification

**Status:** Proposed implementation specification  
**Document version:** 1.1  
**Date:** 10 August 2026  
**Initial platform:** iPhone, iOS 18 or later  
**Implementation language/UI:** Swift 6.x, SwiftUI  

## 1. Product summary

papaSteps is an outdoor walking companion. The user starts a walk, sees useful live information while moving, and ends with a clear, attractive summary and route map. The first release is local-first and privacy-first. It must also establish a clean walk-data foundation that can later support history, weekly comparisons, personal bests, goals, badges, and challenges.

The app must never present missing, stale, or low-quality sensor data as a trustworthy zero. Where a metric is unavailable, the interface must explain that briefly and continue to provide the metrics that are available.

## 2. Goals

The first complete release will:

- Let the user explicitly start, pause, resume, and finish an outdoor walk.
- Show elapsed time, moving time, live steps, walking speed, direction of travel, current altitude, and elevation gained.
- Record a filtered GPS route and display it on a map during and after the walk.
- Persist completed walks and show a history and walk-detail view.
- Enrich the completed walk, when permissioned data exists, with average heart rate and walking asymmetry.
- Continue recording through normal screen locking and app backgrounding.
- Detect a likely prolonged stop and ask whether the user has finished, without silently ending a valid walk.
- Save an optional walking workout and route to Apple Health when the user enables that feature.
- Provide test seams so sensor streams, time, permissions, and persistence can be replaced by deterministic fakes.

## 3. Non-goals for the first release

- Turn-by-turn navigation or route planning.
- Medical diagnosis, gait diagnosis, fall detection, or claims that a gait value is clinically significant.
- A watchOS app in the initial iPhone MVP.
- Social accounts, leaderboards, cloud sync, or a server backend.
- Reliable indoor routing or direction of travel. Indoor walks may retain steps, duration, and available pedometer distance, but GPS route/direction should be marked unavailable.
- Automatically ending a walk without confirmation.

## 4. Product assumptions and decisions

1. **Outdoor walking is the primary v1 mode.** Route, travel direction, and GPS speed require usable outdoor location data.
2. **Manual Done remains authoritative.** Stop detection produces a confirmation prompt; it does not silently complete the session.
3. **Moving time and elapsed time are distinct.** Waiting at a crossing or responding to a finish prompt must not make the walking-speed calculation misleading.
4. **On-device data is canonical.** SwiftData stores papaSteps walk records and track points. HealthKit is a permissioned health/workout integration, not the app's live database.
5. **Optional metrics stay optional.** Heart rate, walking asymmetry, absolute altitude, cadence, and floor count depend on hardware, permissions, placement, and available samples.
6. **Metric provenance is retained.** The app stores the source measurements needed to explain why the displayed distance or step count was chosen.

## 5. Sensor and data-source strategy

Apple Health is not sufficiently immediate to be the only live source. The live session combines Core Motion and Core Location, then uses HealthKit for health enrichment, reconciliation, and optional workout storage.

| Metric | Live primary source | Fallback or post-walk source | Rules |
|---|---|---|---|
| Steps | `CMPedometer` updates from the session start | HealthKit `stepCount` over the session interval | Display session pedometer steps when available. Live updates are cumulative from the supplied start date and are delivered only while the process is running, so pause/resume bookkeeping and foreground backfill are mandatory (§5.1). Retain both values if HealthKit later differs; never add them together. HealthKit reads must be source-filtered (§5.2). |
| Distance | Filtered accepted `CLLocation` point-to-point distance for a good outdoor route | `CMPedometer.distance`, then HealthKit `distanceWalkingRunning` | Prefer route distance only when location coverage/accuracy passes the quality gate. Use pedometer distance for degraded or indoor sessions. HealthKit reads must be source-filtered (§5.2). |
| Current speed | Valid `CLLocation.speed` plus `speedAccuracy`, smoothed over a short rolling window | Reciprocal of `CMPedometer.currentPace` when available | Ignore negative, stale, or inaccurate values. Show `—`/“Acquiring” rather than zero until trustworthy. |
| Average speed | Canonical distance divided by moving time | None | Do not divide by total elapsed time. Preserve elapsed time as a separate stat. |
| Direction of travel | Valid `CLLocation.course` plus `courseAccuracy`, circularly smoothed | Last recently valid course | Course describes travel direction. A compass/device heading describes how the phone is pointed and must not be mislabeled as walking direction. Below the movement threshold, show “Start walking” or the last value as stale. |
| Current altitude | `CMAltimeter` absolute altitude where supported | `CLLocation.altitude` with valid `verticalAccuracy` | Display meters/feet according to user settings and expose an accuracy/unavailable state. Absolute altitude is device-gated **and** depends on location services, so it may report unavailable or yield no samples until location authorization is granted (§5.3). |
| Elevation gained | Noise-filtered positive changes from `CMAltimeter.relativeAltitude` | Filtered route altitude when relative altitude is unavailable | Gain is accumulated ascent, not simply end altitude minus start altitude. Use hysteresis/smoothing to avoid counting sensor noise. Floors ascended may be supplementary only. |
| Walking/stationary state | `CMMotionActivityManager` confidence plus pedometer and speed evidence | Location stationary events | Never act on one classifier flag alone. Multiple Core Motion activity flags may be true. |
| Average heart rate | HealthKit heart-rate samples intersecting the walk interval | None | Optional. iPhone has no heart-rate sensor; useful coverage normally requires Apple Watch or another paired sensor. Show sample coverage and refresh after delayed Health sync. |
| Walking asymmetry | HealthKit `walkingAsymmetryPercentage` samples intersecting the walk interval | None | Optional post-walk metric only. Apple records it under suitable conditions on supported iPhones; it may be absent for a specific walk. Show sample count/coverage and never turn absence into `0%`. |
| Route map | Accepted Core Location samples | None | Store the app's filtered points locally and render a `MapPolyline`. Optionally associate the same route with the HealthKit workout. |

Apple documents that walking-asymmetry samples require suitable steady, flat walking with the phone carried near the waist, and that only about 10–30 samples may be recorded on a typical day. Apple also documents that iPhone heart-rate collection needs an external sensor. These limitations are part of the product, not error cases to hide. See [Walking asymmetry percentage](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/walkingasymmetrypercentage) and [Creating a workout route](https://developer.apple.com/documentation/healthkit/creating-a-workout-route).

On iPhone, workouts are built with `HKWorkoutBuilder` (§13.2). `HKWorkoutSession` is watchOS-only and is relevant only to the future companion described in §13.3; it must not appear in iPhone code.

### 5.1 Pedometer continuity and backfill

`CMPedometer` has two properties that the session logic must handle explicitly, because getting either wrong corrupts the headline step count.

**Cumulative values.** `startUpdates(from:)` reports totals accumulated since the supplied start date, not deltas. Pause must snapshot the cumulative value at pause time and resume must subtract the interval accrued while paused, so steps taken during a pause never enter the walk total. The session therefore tracks a running paused-steps offset alongside the raw cumulative reading, and both are retained for diagnostics.

**Delivery only while running.** There is no Core Motion background execution mode. Live pedometer updates are delivered only while the app process is running; during an active walk the location session normally keeps the process alive, but this is not guaranteed and must not be relied upon. The app must therefore reconcile with `queryPedometerData(from:to:)`:

- on every return to the foreground and on resume from a background-suspended state;
- at each periodic checkpoint during an active walk; and
- once more at finalization, covering the full walk interval.

The query result is authoritative over the accumulated live total for any interval where the two disagree, minus the paused-steps offset. The system retains queryable pedometer history for approximately seven days, which comfortably covers any realistic recovery window. This behavior is implemented in Phase 1 but only becomes observably necessary under the locked-screen and background conditions validated in Phase 4; see the dependency note in that phase.

### 5.2 HealthKit source filtering

HealthKit stores step and distance samples from every contributing device. A user wearing an Apple Watch has overlapping `stepCount` and `distanceWalkingRunning` samples from both iPhone and Watch for the same walk. A cumulative-sum statistics query sums all matching samples and will therefore report substantially inflated totals — the Health app's own de-duplication is a presentation behavior and is not reproduced by the query API.

Every HealthKit step or distance read used for reconciliation must therefore constrain its predicate to a single, deliberately chosen source (for example via `HKSourceQuery` or an explicit `HKSource`/`HKDevice` predicate), and must record which source was used in the walk's provenance fields. An unfiltered cumulative-sum query over these types is a defect, not a simplification. Heart rate and walking asymmetry are unaffected in practice because they originate from one device, but the same predicate discipline should be applied for consistency.

### 5.3 Absolute altitude gating

`CMAltimeter` absolute altitude is limited to supported hardware and additionally depends on location services, because the value is fused with GPS. Availability checks may report unavailable, or the stream may deliver no samples, until location authorization has been granted.

Consequently the diagnostics screen and the device-support matrix must distinguish three states rather than two: hardware absent, hardware present but blocked by a missing permission, and available. Conclusions about the minimum supported device matrix (§17 item 4) must be drawn only after location authorization has been granted on the test device. Relative altitude has no such dependency and remains the preferred ascent signal (§6.4).

## 6. Metric quality and fusion rules

All numerical thresholds below must live in a central `TrackingConfiguration`, be covered by unit tests, and be tuned during real-device field testing rather than scattered through UI code.

### 6.1 Location acceptance

A location point is eligible only when:

- its timestamp is recent enough for the current processing window;
- `horizontalAccuracy` is non-negative and within the configured maximum (initial field-test value: 50 m, with a tighter preference near 20–25 m);
- it does not imply an impossible walking jump relative to the prior accepted point; and
- its timestamp is later than the prior accepted point.

Keep enough information to calculate a route quality result such as `good`, `degraded`, or `unavailable`. Track coverage duration, accepted/rejected point counts, median horizontal accuracy, and the longest gap. Apple recommends filtering inaccurate route locations and keeping useful route samples no more than roughly three seconds apart when possible.

**Reduced accuracy is a distinct, first-class case.** A user may grant When In Use authorization with Precise Location turned off. The resulting coarse fixes are typically one to several kilometres wide, so every point fails the acceptance gate above and the route silently becomes permanently unavailable — an outcome indistinguishable, from the user's side, from the app being broken.

The app must therefore inspect `CLLocationManager.accuracyAuthorization` before and during a walk, and must not treat `.reducedAccuracy` as a location failure. Required behavior:

- Detect reduced accuracy explicitly and surface a specific, non-accusatory explanation naming the affected metrics: route map, route distance, GPS speed, and direction of travel.
- Offer `requestTemporaryFullAccuracyAuthorization(withPurposeKey:)` with a purpose key dedicated to route recording, in context at walk start rather than on first launch.
- If full accuracy is declined or the request is unavailable, continue the walk with pedometer steps, pedometer distance, moving time, and relative elevation gain, and mark route quality `unavailable` with reduced accuracy recorded as the reason.
- Never accumulate route distance from coarse fixes, and never draw a polyline from them.

Reduced accuracy is recorded in the walk's route-quality metadata so that a later support diagnosis, and any Phase 6 eligibility rule, can tell it apart from ordinary GPS degradation.

### 6.2 Speed

- Validate `speed >= 0`, the point's freshness, and `speedAccuracy` when supplied.
- Apply a median or exponential smoothing window that reacts within a few seconds but avoids a visibly jumping value.
- Treat sustained values below the configured walking-motion threshold as stationary for moving-time purposes.
- Store average speed and optionally maximum sustained speed; do not label a single GPS spike as maximum walking speed.

### 6.3 Direction

- Accept course only when it is non-negative, its accuracy is acceptable, and the person is moving fast enough for course to be meaningful.
- Smooth angles with circular math so the transition from 359° to 1° does not swing through 180°.
- Display an arrow, degrees, and a localized cardinal label (for example, `NE · 045°`).
- Make stale direction visually distinct and accessible to VoiceOver.

### 6.4 Elevation gain

- Use relative barometric altitude as the preferred ascent signal because raw GPS altitude is noisy.
- Low-pass filter the stream and accumulate only confirmed positive changes that exceed a configurable noise/hysteresis band.
- Do not count pressure drift while stationary as climbed elevation.
- Preserve raw start/end altitude, relative change, accumulated ascent, source, and quality so the algorithm can evolve without corrupting old walks.

**Relative altitude is measured from the moment updates start.** `CMAltimeter.startRelativeAltitudeUpdates` reports change relative to the point at which that call was made, so every stop and restart of the stream resets the reported baseline to zero. If pause stops altimeter updates and resume restarts them, previously accumulated ascent is silently discarded and the walk under-reports every climb that preceded a pause.

The accumulated-ascent total is therefore owned by the fusion engine, not by the sensor stream. Either keep the altimeter running across pause, or carry the accumulator across restarts and treat each restart as a new baseline whose first sample contributes no gain. The same rule applies after any background-driven restart of the stream and after checkpoint recovery. A regression test must cover pause/resume and stream-restart sequences and assert that accumulated ascent is monotonic across them.

### 6.5 Canonical summary values

Store the source values (`routeDistance`, `pedometerDistance`, `motionSteps`, `healthSteps`) and the selected value/source (`displayDistance`, `distanceSource`, `displaySteps`, `stepSource`). Selection is deterministic and testable. A later HealthKit refresh may enrich an existing record, but must not silently replace a good locally recorded value without applying the documented selection rule.

### 6.6 Moving time reconstruction

Moving time accrues live by sampling movement evidence: each tick adds its interval when a location fix or a step increase landed within `movementEvidenceInterval`. **This measures how often the evidence arrives, not how long the person walked.** `CMPedometer` callbacks are irregular and stop entirely while the process is suspended (§5.1), and GPS speed from a pocketed phone routinely fails the `speedAccuracy` gate, so evidence can arrive far less often than the freshness window consumes it. Observed in the field: a nine-minute walk with the phone in a back pocket recorded 35 seconds of moving time while its step count was correct.

Steps are already reconciled after the fact against `queryPedometerData`. Moving time must be too:

- At finalization, query pedometer history in buckets covering the whole walk, widening the bucket rather than exceeding a query cap on long walks.
- Convert each bucket to time walking as `steps / assumedWalkingCadence`, capped at the bucket's own duration. A bucket with no steps contributes nothing.
- Remove paused windows before conversion. The engine therefore retains pause *windows*, not only a paused-duration scalar, and carries them through checkpoint and restore.
- Record `min(max(live, reconstructed), elapsed − paused)`. The live figure is kept where it is larger, because it is the only one that sees a walk with no step data at all; the clamp guarantees moving time can never exceed the time the walk was running and unpaused.

The live display continues to show the sampled figure — it is honest about what is known second by second — and the saved walk carries the reconstructed one. Because eligibility for Progress (§15, Phase 6) requires a minimum moving duration, an under-counted moving time silently excludes real walks from every weekly total, streak, and personal best; that is the practical cost of getting this wrong.

## 7. User experience

### 7.1 App shell

Use a scalable `TabView`, with an independent `NavigationStack` for each tab:

1. **Walk** — start screen, live walk, pause/finish flow.
2. **History** — completed walks and walk detail.
3. **Progress** — initially a small weekly summary or a clearly scoped future phase; later contains personal bests, comparisons, goals, and achievements.
4. **Settings** — may initially be reached from the Walk tab toolbar rather than taking permanent tab space.

### 7.2 Start screen

- A single prominent **Start Walk** control.
- A compact readiness panel for Motion, Location, Health enrichment, and notifications.
- Permission requests occur in context, not as a wall of prompts on first launch.
- Health access is optional; refusing it must not prevent a basic walk.

### 7.3 Live walk screen

The glanceable hierarchy should be:

1. Large direction arrow/cardinal direction and recording state.
2. Speed (with optional pace toggle).
3. Steps, moving time, altitude, and elevation gain.
4. A route map that follows the user but permits temporary manual panning.
5. Pause/Resume and a deliberate **Done** action.

Use high contrast, semantic colors, large tap targets, Dynamic Type, and concise VoiceOver values. Do not require the user to study the phone while crossing a road. Haptics and spoken announcements may be added later as opt-in settings.

### 7.4 Finish flow

- Done opens a confirmation sheet with Finish Walk, Keep Walking, and Discard options.
- Finishing transitions to a finalizing state while pending persistence and HealthKit enrichment work is handled.
- The summary opens as soon as local core stats are safe; optional Health metrics may show “Checking Health…” and update later.
- Discard is a destructive action and requires explicit confirmation. Discard is a hard delete: the draft, its checkpoints, and its track points are removed permanently, no `WalkRecord` is created, and nothing is written to HealthKit. There is no trash, no soft-delete flag, and no recovery path, and the confirmation copy must say so plainly.

### 7.5 Summary and walk detail

- Hero: route map with start/end markers.
- Primary cards: distance, steps, moving time, average speed.
- Terrain cards: current/end altitude, total ascent, optional descent/floors.
- Health cards: average heart rate and walking asymmetry when samples exist.
- Context: start time, elapsed time, pauses, route quality, and metric availability explanations.
- Optional comparison chip, added only when enough history exists (for example, “12% farther than your 4-week average”).

## 8. Walk lifecycle and state machine

`WalkSessionStore` is a `@MainActor @Observable` app model with an explicit state machine:

```text
idle            -> preparing
preparing       -> active | recoverableFailure
active          <-> paused
active          -> finishCandidate | finalizing
paused          -> finalizing
finishCandidate -> active | paused | finalizing | idle
finalizing      -> completed | recoverableFailure
completed       -> idle

preparing | active | paused | finalizing -> recoverableFailure
recoverableFailure -> active | paused | finalizing | idle
```

Transition notes:

- `finishCandidate -> finalizing` is the path taken when the user confirms Finish from the in-app prompt, the local notification action, or the Live Activity action (§12.2). Without it the stop detector has no way to complete a walk.
- `finishCandidate -> paused` covers a candidate raised while the walk is already paused; resolving the candidate must return to the state the walk was actually in.
- `finishCandidate -> idle` is the explicit destructive discard path. It stops sensor services and creates no `WalkRecord`; the confirmation must state that this cannot be undone.
- `paused -> finalizing` covers finishing directly from a paused walk, which is a normal user flow.
- `completed -> idle` is the reset that permits the next walk; it must publish the completed record before clearing session state.
- `recoverableFailure` must have an exit for every entry. Recovery returns to the pre-failure state where the session is still viable, to `finalizing` where the walk can be salvaged and closed at its last checkpoint, or to `idle` where the user discards it. A state with no exit is a hang, not a failure mode.

Rules:

- Only the state machine may start or stop sensor services.
- Start is idempotent; rapid double taps cannot create two sessions.
- Pause stops adding moving time and route distance but keeps enough monitoring to support resume. Pause must also snapshot the cumulative pedometer reading and preserve the accumulated-ascent total, per §5.1 and §6.4.
- Finalize is idempotent and produces at most one completed `WalkRecord` and at most one HealthKit workout.
- The active draft is checkpointed so a terminated/relaunched app can offer Resume, Finish at last checkpoint, or Discard.
- Sensor callbacks never mutate SwiftUI state directly; they feed typed events into the coordinator/fusion engine.

## 9. Modern architecture

Use SwiftUI's Model–View style rather than creating a view-model type for every screen.

### 9.1 Components

```text
SwiftUI Views
    |
    v
@MainActor WalkSessionStore / App Routers
    |
    +--> WalkSessionCoordinator (lifecycle/state machine)
    +--> WalkMetricsEngine actor (validation, smoothing, fusion)
    +--> WalkRepository (SwiftData implementation)
    +--> HealthClient (HealthKit implementation)
    +--> MotionClient (Core Motion implementation)
    +--> LocationClient (Core Location implementation)
    +--> NotificationClient / Live Activity client
```

### 9.2 Architectural requirements

- Define narrow protocols for each external framework boundary.
- Production sensor adapters expose `AsyncStream`/`AsyncThrowingStream` values; tests inject deterministic streams.
- Keep units explicit in domain types (`meters`, `metersPerSecond`, `degrees`, `beatsPerMinute`) and format only in the presentation layer.
- Keep `ModelContext` and SwiftData model instances on their owning actor. Send immutable `Sendable` snapshots/identifiers across actor boundaries and refetch when needed.
- Explicitly save at meaningful checkpoints and finalization; do not rely solely on SwiftData autosave.
- Version the SwiftData schema from the first release and define migration plans as the model evolves.
- Use dependency injection at the app entry point. Avoid global singletons, even where a single underlying `HKHealthStore` or motion manager is required.
- No third-party runtime dependency is required for the initial app.

### 9.3 Suggested feature-first project layout

```text
papaSteps/
  App/
  Domain/
    Walk/
    Metrics/
  Features/
    Walk/
    History/
    Progress/
    Settings/
  Services/
    Health/
    Motion/
    Location/
    Notifications/
  Persistence/
    Models/
    Repositories/
    Migrations/
  DesignSystem/
  Support/
papaStepsTests/
papaStepsUITests/
```

## 10. Persistence model

### 10.1 `WalkRecord`

Required fields:

- Stable app UUID, schema version, created/updated timestamps.
- Start, end, elapsed duration, moving duration, and paused duration.
- The `TimeZone` identifier in effect at walk start, stored as a string alongside the UTC start instant.
- State/finalization status and optional recovery metadata.
- Canonical distance, distance source, route/pedometer/Health distances.
- Canonical steps, step source, motion/Health step counts.
- Average speed and optional maximum sustained speed.
- Start altitude, end altitude, elevation gain/loss, altitude source/quality.
- Average heart rate, heart-rate sample count, covered duration/quality.
- Walking asymmetry average, sample count, covered duration/quality.
- Route quality and accepted/rejected point counts.
- Optional HealthKit workout UUID and Health enrichment status/date.

Index stable UUID and start date. Weekly/history queries should read summaries without loading every route point.

**Why the timezone identifier is stored.** A UTC instant alone cannot be assigned to a local calendar week after the fact, because the user's zone may have changed since the walk. Phase 6 requires each walk to fall in exactly one documented local week even across a timezone change, so the zone in effect at walk start is captured with the record and is the only zone used to bucket it thereafter. The field is added in the Phase 2 schema, not Phase 6, so that no migration is needed to enable aggregation.

**Eligibility is derived, not stored.** Discarded walks are hard-deleted (§7.4) and therefore never reach persistence, so no discarded flag exists or is needed. Some retained walks are nonetheless ineligible for personal bests and comparisons — for example those below a minimum duration or distance, or whose route quality is `unavailable`. Eligibility is a deterministic predicate evaluated from the stored fields above by a versioned `WalkEligibilityRules` type in the domain layer, never inline in view or query code.

Store the eligibility-rules version applied at finalization so that a later rule change is explainable against historical records and can be recomputed rather than guessed. Because eligibility is derived, tightening the rules never rewrites stored walk data.

### 10.2 `WalkTrackPoint`

- Stable UUID and parent walk relationship.
- Timestamp, latitude, longitude, altitude.
- Horizontal/vertical accuracy.
- Speed/speed accuracy and course/course accuracy when valid.
- Point acceptance/quality information if diagnostic retention is enabled.

Use an explicit cascade delete from `WalkRecord` to track points and an explicit inverse relationship. Save points in sensible batches/checkpoints rather than saving the database for every sensor callback.

### 10.3 Analytics boundary

`WalkAnalyticsService` consumes summary snapshots, not SwiftUI views or live sensor services. It calculates daily/weekly aggregates, streaks, baselines, personal bests, and comparison text. Start with on-demand calculations; add cached aggregate models only if profiling demonstrates a need.

## 11. Permissions, capabilities, and privacy

### 11.1 Required project configuration

- Motion usage description (`NSMotionUsageDescription`).
- Location When In Use usage description (`NSLocationWhenInUseUsageDescription`).
- Temporary full-accuracy purpose strings (`NSLocationTemporaryUsageDescriptionDictionary`), containing a purpose key dedicated to route recording, so full accuracy can be requested when the user has granted location with Precise Location off (§6.1).
- Health share description for reads (`NSHealthShareUsageDescription`).
- Health update description only if the user enables writing workouts/routes (`NSHealthUpdateUsageDescription`).
- HealthKit capability; workout-route types only when implemented.
- Background Modes → Location updates for active walks in the background.
- Notification permission only when the finish-reminder feature is enabled.
- Live Activities/App Intents capabilities when the Lock Screen experience is implemented.

### 11.2 Permission behavior

- Ask for Motion and Location when the user starts the first walk and has seen the benefit explanation.
- Ask for Health access from an optional “Add Health insights” step or Settings.
- Request only workout, route, step count, walking/running distance, heart rate, and walking asymmetry types actually used by the current build.
- Health read denial is privacy-preserving and may appear identical to no data; the UI must not accuse the user of denial.
- Provide Settings links for denied Motion/Location permissions.
- Treat authorization and accuracy as two separate questions. Granted location with reduced accuracy is a supported configuration, not a denial: request temporary full accuracy in context at walk start, and if it is declined, continue with the non-location metrics and an honest route-unavailable explanation (§6.1).
- Never upload health or precise route data in v1. Any future sync/export requires a separate threat model, privacy policy update, user consent, and retention/deletion design.

## 12. Background recording and likely-stop detection

### 12.1 Background lifecycle

During an active walk, hold a `CLBackgroundActivitySession` and a fitness-configured location update stream. This supports background location with When In Use authorization while the app remains active/suspended and displays the system location indicator. Do not request Always authorization for the MVP.

Checkpoint the active draft periodically and at app lifecycle changes. A normal screen lock must not end the session. If a process termination prevents continued sampling, relaunch recovery must be truthful about the gap rather than interpolating imaginary points.

#### 12.1.1 Permission changes during an active walk

A user can revoke or downgrade Motion or Location authorization in Settings while a walk is running, and some of those changes terminate the app. This is not a crash and must not be reported as one, because the user's own action caused it and the walk genuinely cannot continue as before.

Required behavior:

- Observe authorization and accuracy changes for the whole active-walk lifetime, not only at start.
- If location is revoked or downgraded to reduced accuracy mid-walk, stop accepting route points at that instant, freeze route distance at its last good value, mark route quality accordingly with the reason recorded, and continue the walk with pedometer steps, moving time, and relative elevation gain.
- If motion is revoked mid-walk, stop step and altimeter accumulation and mark those metrics unavailable from that point, retaining the values already accumulated.
- Never silently finalize a walk because a permission changed.
- On relaunch after a permission-triggered termination, the recovery prompt must name the cause specifically — the walk stopped because access was changed in Settings — and offer the same choices as any other interrupted draft: resume, finish at the last checkpoint, or discard. Truthfulness about the gap (§12.1) applies unchanged.

### 12.2 Stop detector

The detector emits `finishCandidate` only after a configurable period (initial field-test value: 3 minutes) with corroborating evidence:

- no meaningful step increase;
- speed below the stationary threshold;
- little accepted displacement; and
- stationary Core Motion classification with adequate confidence where available.

Behavior:

- Foreground: show “Have you finished your walk?” with Finish and Keep Walking.
- Background/locked: schedule a local notification with Finish and Keep Walking actions; expose the active walk through a Live Activity when that phase is implemented.
- Keep Walking dismisses the candidate and applies a short suppression period.
- Movement resumes the active state automatically and cancels a pending prompt.
- No response does not silently finish. Moving time remains based on movement detection, so a long stationary interval does not inflate average walking speed.

## 13. HealthKit enrichment and export

### 13.1 Read enrichment

After local finalization:

1. Query heart-rate samples over the walk interval and calculate a discrete average plus coverage metadata.
2. Query walking-asymmetry samples overlapping the interval and calculate a discrete average plus sample count.
3. Optionally query Health steps/distance for reconciliation, source-filtered as required by §5.2 and recording which source was used. An unfiltered cumulative-sum query over these types will double-count an Apple Watch wearer's walk and must not ship.
4. Persist available results and an enrichment timestamp.
5. Allow a manual refresh because Apple Watch/Health synchronization may be delayed.

### 13.2 Optional workout write

When enabled, build and save one outdoor walking workout and associate filtered route locations with it using `HKWorkoutBuilder`/`HKWorkoutRouteBuilder`. Obtain the route builder from `HKWorkoutBuilder.seriesBuilder(for:)`; the parent workout builder owns and finishes that route when `finishWorkout()` runs, so this path must not also call `finishRoute(with:metadata:)`. Quantity samples added to the builder must start later than the workout-builder start date, even when they summarize the full walk. Apple documents the overall route flow in [Creating a workout route](https://developer.apple.com/documentation/healthkit/creating-a-workout-route).

**Idempotency must not depend on the locally stored workout UUID alone.** Storing the returned HealthKit UUID after a successful write is necessary but insufficient, because it leaves an unguarded window: if the process is terminated after the workout is finished in HealthKit but before the local save commits, the local record shows no workout, and the retry writes a second one. The user then sees a duplicate walk in Health that the app has no record of and cannot clean up.

The local walk UUID is therefore the correlation key, carried in HealthKit itself:

1. Write the local walk UUID into the workout's `metadata` under a dedicated app-defined key at build time.
2. Before any write or retry, run an `HKSampleQuery` for workouts predicated on that metadata key matching this walk's UUID.
3. If a match exists, adopt its HealthKit UUID into the local record and perform no write. If none exists, write.
4. Persist the returned HealthKit UUID locally as a fast path, treating it as a cache of step 2 rather than the source of truth.

This makes the write idempotent across process termination at any point in the sequence, which is what P3-06 exercises. The same correlation key allows a future support or cleanup path to identify workouts this app created.

### 13.3 Future watchOS extension

A watchOS companion is a separate later project phase. It can run an Apple Watch workout session, collect high-frequency heart rate, show wrist metrics, and mirror the session to iPhone. The iPhone-only architecture must not pretend it already provides Watch-grade continuous heart-rate recording.

## 14. Testing strategy

### 14.1 Automated tests

- State-machine transition and idempotency tests, covering every transition listed in §8 — including `finishCandidate -> finalizing`, `paused -> finalizing`, `completed -> idle`, and an exit from `recoverableFailure` for every entry into it — and asserting that no state is reachable without an exit.
- Location acceptance, jump rejection, distance accumulation, and route quality tests.
- Reduced-accuracy tests: coarse fixes never accumulate distance or produce a polyline, route quality records reduced accuracy as the reason, and non-location metrics continue.
- Speed smoothing and stale-value tests.
- Circular direction smoothing tests, including 359° → 1°.
- Elevation smoothing, hysteresis, ascent/descent, and pressure-drift tests.
- Altimeter baseline tests: accumulated ascent is monotonic across pause/resume, stream restart, and checkpoint recovery, and a restart's first sample contributes no gain.
- Pedometer tests: cumulative-value handling, paused-steps offset, backfill reconciliation where the queried interval disagrees with the accumulated live total, and no double counting when both paths cover the same interval.
- Moving-time versus elapsed-time tests.
- Stop-detector true-positive, false-positive, suppression, and movement-resume tests.
- Canonical metric source-selection/reconciliation tests, including a multi-source HealthKit fixture proving that step and distance reads are source-filtered and do not double-count an Apple Watch wearer.
- Health metric tests for available, delayed, empty, denied/indistinguishable, and malformed samples.
- Workout-write idempotency tests driving termination at each point in the §13.2 sequence, asserting exactly one workout per local walk UUID.
- Mid-walk permission revocation and accuracy-downgrade tests for both Motion and Location.
- Eligibility-rule tests, including rule-version changes recomputed against historical records.
- SwiftData in-memory repository tests, cascade-delete tests, checkpoint recovery, and migration tests.
- Formatter tests for metric/imperial units and pace/speed.
- UI tests for start, pause, resume, Done confirmation, recovery, missing metrics, and History navigation.

### 14.2 Test infrastructure

- Injectable clock and UUID generator.
- Fake Motion, Location, Health, Notification, and Live Activity clients.
- GPX routes for straight walking, turns, hills, GPS gaps, and impossible jumps.
- Recorded anonymized sensor fixtures from real-device field tests, committed only with explicit consent and location redaction.
- Debug diagnostics screen showing source values, accuracy, point acceptance, and rejection reasons.

## 15. Phased implementation plan

Each phase ends in a usable, demonstrable build. The AI agent should not begin the next phase until automated checks pass and the manual exit scenarios are accepted on a physical iPhone where required.

### Phase 0 — Project foundation and sensor feasibility

**Build**

- Create the iOS project, test targets, feature-first folders, dependency container, app tab shell, and in-memory/preview fakes.
- Add a debug-only sensor capability screen for Motion, pedometer features, relative/absolute altitude, Location authorization/accuracy, and Health availability. Capability reporting must distinguish hardware absent, blocked by a missing permission, and available (§5.3), and must show location accuracy authorization separately from authorization status.
- Establish the SwiftData v1 schema/migration plan and a repository smoke test.
- Add CI commands for build, unit tests, and lint/format only if a formatter is deliberately selected.

**Automated exit gate**

- Clean build and test pass.
- Fakes can drive the app through idle → preparing → active → finalizing → completed without using Apple frameworks.
- In-memory persistence creates, fetches, and cascade-deletes a sample walk.

**Your manual test scenarios**

| ID | Scenario | Expected result |
|---|---|---|
| P0-01 | Launch on a physical iPhone | App opens to Walk tab; no permission wall appears. |
| P0-02 | Open diagnostics before granting access | Hardware availability is reported without a crash; features say unavailable, and anything gated on a permission says so rather than being reported as missing hardware. |
| P0-03 | Grant Motion and When In Use Location | Status changes to ready and a valid location eventually appears. Re-check absolute altitude here, after location is granted, before recording any conclusion about device support (§5.3). |
| P0-03b | Grant location with Precise Location off | Diagnostics reports reduced accuracy distinctly from denied; the app offers the temporary full-accuracy request rather than treating it as a failure. |
| P0-04 | Deny one permission | App explains the affected metrics and offers Settings; unrelated diagnostics still work. |
| P0-05 | Launch in Simulator | App remains usable with clear simulated/unavailable sensor states. |

### Phase 1 — Manual live-walk MVP

**Build**

- Start, pause, resume, Done, discard, and finalization state machine.
- Live pedometer steps, elapsed/moving time, smoothed GPS speed, course/cardinal direction, absolute altitude, and relative elevation gain.
- Pedometer cumulative-value handling, paused-steps offset, and `queryPedometerData(from:to:)` backfill on foreground, checkpoint, and finalization (§5.1).
- Fusion-engine ownership of accumulated ascent across altimeter stream restarts (§6.4).
- Metric availability/stale/accuracy states, including reduced location accuracy and the in-context temporary full-accuracy request (§6.1).
- A lightweight current-position map; full route persistence follows in Phase 2.
- Unit tests for fusion algorithms and lifecycle behavior.

**Automated exit gate**

- Deterministic streams reproduce expected steps, distances, direction changes, and ascent.
- Invalid/stale/low-accuracy values never appear as valid zeroes.
- Double Start/Done calls do not duplicate sessions.

**Your manual test scenarios**

| ID | Scenario | Expected result |
|---|---|---|
| P1-01 | Start and walk outdoors for at least 5 minutes | Steps and moving time increase; speed settles to a plausible value. |
| P1-02 | Walk a route with two clear 90° turns | Direction changes after movement resumes and does not oscillate wildly while stopped. |
| P1-03 | Walk up a known hill/stair section | Relative elevation gain increases plausibly and does not fall when walking downhill. |
| P1-04 | Stand still for 60 seconds | Moving time/speed respond appropriately; elapsed time continues; direction becomes stale instead of random. |
| P1-05 | Pause, move, then resume | Paused movement does not add to walk distance/moving time; recording continues after Resume. |
| P1-06 | Tap Done then Keep Walking | Session returns to active with prior metrics intact. |
| P1-07 | Finish a walk | One local summary is created; buttons cannot create duplicates. |

### Phase 2 — Route, persistence, history, and core summary

**Build**

- Filter, batch, checkpoint, and persist track points.
- Live route polyline and post-walk map with start/end markers and route framing.
- Canonical distance selection and route-quality metadata, including reduced accuracy as a recorded quality reason.
- The walk-start `TimeZone` identifier in the persisted schema, added now so Phase 6 needs no migration (§10.1).
- SwiftData History list and Walk Detail.
- Draft recovery after ordinary app relaunch, and after a permission-triggered termination with the cause named (§12.1.1).

**Automated exit gate**

- GPX fixtures yield expected distance within defined tolerance and reject injected jumps.
- Summary/history fetches do not load all track points until detail requires them.
- Deleting a walk cascade-deletes its track points.
- An interrupted draft is recoverable without becoming a completed record automatically.

**Your manual test scenarios**

| ID | Scenario | Expected result |
|---|---|---|
| P2-01 | Complete a known 1–2 km route | Summary distance is plausible; map follows the streets/path without a large teleport. |
| P2-02 | Walk where GPS briefly degrades | App marks route quality degraded if needed and does not draw an impossible long spike. |
| P2-03 | Relaunch after a completed walk | Walk appears once in History with the same stats and route. |
| P2-04 | Start a walk, background briefly, then relaunch | App offers a truthful recovery choice for the active draft. |
| P2-05 | Delete a historical walk | It disappears from History after confirmation and remains deleted after relaunch. |
| P2-06 | Walk with Precise Location turned off, declining the full-accuracy request | No route or GPS speed is shown and no polyline is drawn; steps, moving time, and elevation still work; the walk explains which metrics need precise location. |
| P2-07 | Revoke location in Settings mid-walk | Route freezes at its last good value, the walk continues with remaining metrics, and any relaunch names the permission change as the cause. |

### Phase 3 — Health insights and optional Apple Health workout

**Build**

- Contextual Health authorization and graceful partial/denied states.
- Post-walk average heart rate, walking asymmetry, source-filtered Health steps/distance reconciliation (§5.2), coverage labels, and manual refresh.
- Optional walking-workout and route save to HealthKit, made idempotent by the metadata correlation key rather than the locally stored UUID (§13.2).
- Manual review-and-select import of walking workouts from the last 90 days, including an available Health route, source provenance, and UUID-based duplicate prevention. Workouts exported by papaSteps are omitted to prevent an import/export feedback loop.
- Health cards that explain why a value may not be available.

**Automated exit gate**

- Empty Health results produce `nil/not available`, never zero.
- Delayed fake samples update the existing walk rather than create a duplicate.
- Health workout retry cannot write a second workout for the same local UUID, including when the process is terminated after the workout is finished in HealthKit but before the local UUID is saved.
- A multi-source fixture containing overlapping iPhone and Apple Watch samples yields a reconciled step and distance total from one source, not their sum.
- Re-importing the same Health workout UUID updates nothing and creates no duplicate; an imported workout is never exported back to Health.

**Your manual test scenarios**

| ID | Scenario | Expected result |
|---|---|---|
| P3-01 | Decline Health access and finish a walk | Core walk works normally; Health cards show a neutral unavailable explanation. |
| P3-02 | Permit Health with Apple Watch/sensor data present | Average heart rate appears with a sample/coverage indicator. |
| P3-03 | Finish without eligible asymmetry data | Walking asymmetry says Not Available, not `0%`. |
| P3-04 | Carry the iPhone near the waist on a steady flat walk, then refresh later | If Health produces samples, asymmetry appears and is tied to the walk interval; otherwise the honest unavailable state remains. |
| P3-05 | Enable Save to Apple Health and finish | Exactly one outdoor walking workout appears in Health/Fitness with plausible time, distance, and route. |
| P3-06 | Trigger/retry finalization | No duplicate local walk or Health workout appears. |
| P3-07 | Complete a walk while wearing an Apple Watch | Reconciled Health steps and distance stay close to the pedometer values rather than roughly doubling them. |
| P3-08 | Open Apple Health settings, choose Import walking workouts, select one or more walks, and import | Each selected workout appears once in History with a Health source badge and its route when Health provides one. |
| P3-09 | Return to the import screen after importing, with Save new walks to Apple Health enabled | Imported workouts are marked Imported, cannot be selected again, and no duplicate workout is written to Health. |

### Phase 4 — Background robustness, Live Activity, and finish prompting

**Dependency note — pedometer backfill.** The pedometer continuity work in §5.1 is built and unit-tested in Phase 1, but its absence is invisible until this phase: while the screen is on and the app is foreground, live updates alone appear to work perfectly. Phase 4 is the first point at which a missing backfill path shows up, as steps that silently stop accruing during a locked-screen walk. Before starting P4-01, confirm that the Phase 1 backfill and paused-steps offset are actually present and exercised; if that work was deferred or stubbed, complete it here rather than diagnosing it as a background-execution bug. The same applies to the altimeter baseline ownership in §6.4, which a background-driven stream restart will expose for the first time.

**Build**

- `CLBackgroundActivitySession`, background location capability, app lifecycle handling, and periodic checkpoints.
- Live Activity/Lock Screen metrics with pause/resume/finish App Intents where supported.
- Multi-signal likely-stop detector and actionable local notification.
- Resume/cancel behavior when movement restarts.

**Automated exit gate**

- Background/foreground transitions do not start duplicate streams.
- Stop prompt occurs only after the configured corroborated window.
- A short stop, low-confidence classifier, or renewed steps cancels/suppresses the prompt as specified.

**Your manual test scenarios**

| ID | Scenario | Expected result |
|---|---|---|
| P4-01 | Start, lock the phone, walk 10 minutes, unlock | Route and metrics cover the locked period; one session remains active. Steps for the locked interval match a manual count or a second reference device within a small tolerance — neither frozen nor double-counted after backfill. |
| P4-01b | Lock, walk, unlock, then repeat twice in one walk | Each unlock reconciles once; accumulated steps and ascent stay monotonic and are not re-added by successive backfills. |
| P4-02 | Stop for longer than the configured threshold | A finish prompt/notification appears once. |
| P4-03 | Tap Keep Walking, then resume | Prompt dismisses, recording continues, and no immediate repeated prompt occurs. |
| P4-04 | Pause briefly at traffic lights | The app does not complete the walk; movement resumes normally. |
| P4-05 | Finish from the Lock Screen action | App finalizes once and opens the correct summary on next foreground. |
| P4-06 | Force-terminate during a walk, then relaunch | App reports the recording gap and offers recovery; it does not invent route points. |
| P4-07 | Walk 10 minutes with the phone in a pocket and the screen locked | Saved moving time is close to the walked time, not a fraction of it, and average speed is a plausible walking speed. The live figure may lag during the walk; the saved one may not (§6.6). |
| P4-08 | Pause for two minutes mid-walk, walking during the pause | Paused time is excluded from moving time even though steps were recorded, and moving time never exceeds elapsed minus paused. |

### Phase 5 — Field quality, accessibility, privacy, and beta readiness

**Build**

- Accessibility audit, Dynamic Type layouts, VoiceOver metric descriptions, reduced-motion support, and contrast review.
- Metric/imperial units and speed/pace preferences.
- Long-walk memory/database batching, battery, and thermal profiling.
- Privacy copy, data deletion/export decisions, App Store permission text, error logging without health/location payload leakage.
- TestFlight checklist and supported-device matrix.

**Automated exit gate**

- All tests pass in release configuration.
- A long simulated route remains within agreed memory/database performance budgets.
- No sensitive coordinates or Health values appear in production logs/analytics.

**Your manual test scenarios**

| ID | Scenario | Expected result |
|---|---|---|
| P5-01 | Use largest accessibility text size | Primary metrics/actions remain readable and usable without clipped critical content. |
| P5-02 | Navigate with VoiceOver | Every live stat includes name, value, unit, and unavailable/stale state; controls have clear actions. |
| P5-03 | Switch metric/imperial and speed/pace | Current and historical displays update consistently without changing stored base units. |
| P5-04 | Complete a 60–90 minute walk | No runaway memory, excessive route noise, lost session, or unusable battery drain. |
| P5-05 | Walk through a poor-location area | Degraded state is honest and the app continues with non-location metrics. |
| P5-06 | Delete all app data | Local walks/routes are removed; separately saved Health workouts are handled exactly as the UI explains. |

### Phase 6 — Progress and gamification

**Build**

- Weekly distance, duration, steps, and elevation aggregates.
- Personal bests using the versioned `WalkEligibilityRules` predicate from §10.1, not ad-hoc filters in query or view code.
- Compare current week with best week, previous week, and rolling four-week baseline.
- Goals, streaks, and badges driven by versioned domain rules, not hardcoded view logic.
- Progress tab charts using the same repository/analytics boundary.

**Automated exit gate**

- Calendar/time-zone and week-boundary tests (including Monday-first locale behavior if chosen), bucketing each walk by its stored walk-start timezone identifier rather than the device's current zone.
- Recomputed aggregates match source walks and exclude records the eligibility predicate rejects. Discarded walks require no filtering because discard is a hard delete (§7.4) and they never reach persistence.
- Changing the eligibility-rules version recomputes bests and aggregates from stored fields without rewriting historical walk records.
- Badge/record events are idempotent.

**Your manual test scenarios**

| ID | Scenario | Expected result |
|---|---|---|
| P6-01 | Seed walks across multiple weeks | Weekly totals match the sum of eligible source walks. |
| P6-02 | Exceed a previous best week | Comparison identifies the correct dimension and percentage without overwriting history. |
| P6-03 | Cross a week boundary/time-zone change | Each walk belongs to the documented local week exactly once, determined by the timezone stored at walk start, and does not move between weeks when the device zone later changes. |
| P6-04 | Add/delete an old walk | Affected aggregates and bests recompute correctly. |
| P6-05 | Earn the same badge condition twice | Badge is awarded once and remains explainable from source data. |

## 16. Definition of done for every phase

A phase is complete only when:

- Its scoped behavior is implemented; later-phase placeholders are not presented as working.
- Automated tests and a clean build pass.
- New permissions/capabilities have clear user-facing explanations.
- Errors and missing sensor data degrade safely.
- Cross-component changes (domain, services, persistence, UI, tests, and documentation) agree.
- The listed manual scenarios have results recorded, including device/iOS version and any validation limitation.
- `specification.md` is updated if an accepted implementation decision changes this contract.

## 17. Open product decisions before Phase 1

Phase 1 uses the following provisional implementation defaults: live speed is shown in km/h, pause is manual-only, the software deployment target remains iOS 18, and `papaSteps` remains the working product identity. These defaults can be revisited after the Phase 1 physical-device trials without changing the sensor or persistence architecture.

These decisions do not block Phase 0, but should be resolved before polishing the live UI:

1. Final app name and visual identity (`papaSteps` remains the working identity).
2. Whether to retain the Phase 1 km/h default or add min/km as the default/Settings alternative.
3. Whether to retain manual-only pause after field testing or add automatic stationary pausing.
4. The minimum supported physical-iPhone matrix after checking required altimeter features; the software target is iOS 18.
5. Whether saving to Apple Health is opt-in per walk or a persistent Settings choice.
6. Whether the first Progress tab ships empty, with a simple weekly total, or waits until Phase 6.
7. Exact stop-prompt delay and suppression interval after real-world trials.

## 18. Architectural impact summary

- **Live sensor acquisition:** isolated behind clients so permissions, Apple API changes, and hardware absence do not leak into views.
- **Derived metrics:** centralized in one engine so live display, final summary, Health export, and future gamification use consistent definitions.
- **Persistence:** stores source provenance and quality, enabling later algorithm improvements and honest support diagnostics.
- **History/progress:** depend on summary snapshots, keeping large route-point relationships out of weekly aggregation paths.
- **Background/Health integrations:** added as lifecycle-aware capabilities without becoming prerequisites for the basic walk.
- **Future watchOS/cloud features:** can attach to the coordinator/repository boundaries without replacing the core domain model, while still requiring their own explicit privacy and synchronization designs.
