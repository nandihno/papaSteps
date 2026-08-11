# papaSteps — Which AI Model to Use

**Last checked:** 8 August 2026  
**Related plan:** [`specification.md`](specification.md)

## Quick answer

If choosing only one model for the whole application, use **GPT-5.6 Sol**.

For a more cost-conscious approach:

- Use **Sol** for Phases 0–4.
- Use **Terra** for Phases 5–6.
- Use **Sol** to review the end of every phase before physical-device testing.
- Use **Luna** only for narrow, repetitive work after the design and coding pattern have already been established.

## Recommendation by phase

| Phase | Difficulty | Lead model | Reasoning level | Why |
|---|---|---|---|---|
| **0 — Foundation and sensor feasibility** | High and strategically important | **Sol** | **High** | Architecture, dependency boundaries, SwiftData schema, concurrency isolation, and test infrastructure affect every later phase. |
| **1 — Manual live-walk MVP** | Very high | **Sol** | **xhigh** | Multiple asynchronous sensor streams, smoothing, altitude calculation, stale-data handling, and the walk state machine must agree. |
| **2 — Route, persistence, history, and summary** | High | **Sol** | **High** | GPS filtering, distance selection, batched SwiftData writes, route performance, cascade deletion, and interrupted-walk recovery interact. |
| **3 — Health insights and Apple Health workout** | Very high | **Sol** | **xhigh** | HealthKit permissions and missing/delayed data need careful handling. Workout and route saving must be retry-safe and duplicate-proof. |
| **4 — Background robustness and finish prompting** | **Extreme — the hardest phase** | **Sol** | **xhigh**; consider **max** for final review or difficult bugs | Background location, app lifecycle changes, Live Activities, App Intents, notifications, recovery, and false-positive stop detection all overlap. |
| **5 — Accessibility, privacy, performance, and beta readiness** | Medium coding difficulty; high real-device testing difficulty | **Terra** | **High** | Much of the work is bounded: accessibility, units, profiling fixes, logging hygiene, permission copy, and TestFlight preparation. Use Sol for the final release audit. |
| **6 — Progress and gamification** | Medium to high | **Terra** | **High** | Weekly totals, personal bests, streaks, calendar boundaries, and badge idempotency are complex but deterministic and highly testable. |

## Difficulty order

From hardest to most straightforward:

1. **Phase 4** — Background robustness, Live Activity, recovery, and finish detection.
2. **Phase 1** — Live sensor fusion and walk lifecycle.
3. **Phase 3** — HealthKit enrichment and duplicate-safe workout export.
4. **Phase 2** — Route filtering, persistence, and recovery.
5. **Phase 0** — Not the most complicated code, but mistakes here affect every later phase.
6. **Phase 5** — Mostly bounded coding, but substantial physical-device validation.
7. **Phase 6** — Deterministic analytics and gamification rules.

## What each model should do

### GPT-5.6 Sol

Use Sol for work where an error can create systemic problems:

- Architecture and project foundations.
- Swift concurrency and actor isolation.
- Sensor fusion and metric-quality rules.
- Walk lifecycle and state-machine design.
- Background execution and recovery.
- HealthKit authorization and workout writing.
- SwiftData relationships and migrations.
- Difficult debugging.
- Phase-end architectural and code review.

### GPT-5.6 Terra

Use Terra after the architecture and interfaces are established:

- Routine SwiftUI screens and components.
- History and settings screens.
- Implementing clearly specified repository methods.
- Accessibility improvements.
- Unit formatting and preferences.
- Charts and progress presentation.
- Deterministic weekly aggregation and gamification rules.
- Expanding tests that require some engineering judgment.

### GPT-5.6 Luna

Do not give Luna ownership of a whole papaSteps phase. Use it only for bounded, mechanical tasks such as:

- Adding preview/sample records.
- Expanding an existing test-fixture pattern.
- Adding straightforward formatting tests.
- Applying already-decided accessibility identifiers.
- Documentation cleanup.
- Localization-string preparation.
- Repetitive code changes with an exact nearby pattern.

Do not use Luna to independently design:

- Sensor fusion.
- SwiftData relationships or migrations.
- HealthKit writes.
- Background lifecycle behavior.
- Recovery/finalization logic.
- Metric source-selection rules.

## Recommended workflow for every phase

1. Start the phase with its recommended lead model.
2. Tell the model to read `specification.md` and implement only the current phase.
3. Require it to run the phase's automated tests and a clean build.
4. For large phases, use Terra for routine subtasks only after Sol has established the interfaces and patterns.
5. Return to Sol for a phase-end review covering correctness, architecture, concurrency, privacy, performance, and missing tests.
6. Perform the manual test scenarios from `specification.md` on a physical iPhone.
7. Record the results and proceed only after the automated and manual exit gates pass.

## Important testing reminder

A stronger model cannot replace real-device testing. The following behavior must be verified physically:

- GPS accuracy and route noise.
- Speed and direction stability.
- Barometric altitude drift.
- Background behavior while the phone is locked.
- Battery and thermal impact during a long walk.
- HealthKit and Apple Watch synchronization delays.
- Walking-asymmetry availability.
- Live Activity, notification, and Lock Screen actions.

## Current OpenAI guidance

OpenAI currently describes:

- **GPT-5.6 Sol** as the frontier model for complex professional work.
- **GPT-5.6 Terra** as the balance of intelligence and cost.
- **GPT-5.6 Luna** as the efficient option for cost-sensitive, high-volume work.

OpenAI recommends `high` or `xhigh` reasoning when testing demonstrates a quality gain, and reserving `max` for the hardest quality-first work.

Source: [OpenAI model guidance](https://developers.openai.com/api/docs/guides/latest-model)

Because model availability and guidance can change, recheck the official documentation if development resumes substantially later than the date at the top of this file.
