# Phase 0 validation

Date: 10 August 2026

## Automated gates

Environment: Xcode 26.6 (17F113), iPhone 17 Pro Simulator, iOS 26.5.

| Gate | Result | Evidence |
|---|---|---|
| Debug clean build | Pass | `xcodebuild` completed successfully for the generic iOS Simulator destination. |
| Release build | Pass | Whole-module optimized build completed successfully for arm64 and x86_64 simulator architectures. |
| Unit tests | Pass | Five Swift Testing tests passed, covering the fake lifecycle, duplicate-start protection, schema version, repository persistence/cascade deletion, and reduced-to-full location accuracy behavior. |
| UI launch smoke test | Pass | The app launched on iPhone 17 Pro Simulator without an alert, opened on Walk, and exposed the expected Phase 0 controls. |
| Configuration files | Pass | The app plist, HealthKit entitlement, and Xcode project plist all passed `plutil -lint`. |

## Manual scenarios

| ID | Status | Result or limitation |
|---|---|---|
| P0-01 | User-reported pass | On 11 August 2026 the user confirmed that the app loads on a physical device. The device model and iOS version still need to be recorded. |
| P0-02 | Pending physical device | Requires checking diagnostics before granting Motion and Location permissions. |
| P0-03 | Pending physical device | Requires granting Motion and When In Use Location and confirming a valid location and absolute-altitude result. |
| P0-03b | Pending physical device | Requires disabling Precise Location and exercising the temporary full-accuracy request. |
| P0-04 | Pending physical device | Requires denying one permission and verifying Settings recovery without affecting unrelated diagnostics. |
| P0-05 | Pass | The iOS 26.5 Simulator remained usable and the debug diagnostics screen clearly identified the simulated environment and unavailable sensors. |

Phase 0 is automated-gate complete. It is not device-validation complete until P0-01 through P0-04 are executed and their results are recorded here.
