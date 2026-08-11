import Foundation
import Testing
@testable import papaSteps

/// Guards the rule that no user-facing string is a storage identifier.
///
/// Raw values are camelCase enum cases; anything shown to a user must read as
/// English. These tests fail if a new case is added without a label, or if a
/// label regresses to its raw value.
@MainActor
struct DisplayNameTests {
    /// Matches a lowercase letter immediately followed by an uppercase one —
    /// the signature of `whenInUse`, `notDetermined`, `permissionRequired`.
    private static let camelCasePattern = /[a-z][A-Z]/

    /// Product names are legitimately mid-word capitalized and must not be
    /// mistaken for identifiers leaking into the interface.
    private static let brandNames = ["iPhone", "iPad", "iOS", "papaSteps"]

    private static func strippingBrandNames(_ label: String) -> String {
        brandNames.reduce(label) { $0.replacingOccurrences(of: $1, with: "") }
    }

    private func assertUserFacing<T: UserFacingState & CaseIterable & RawRepresentable>(
        _ type: T.Type,
        sourceLocation: SourceLocation = #_sourceLocation
    ) where T.RawValue == String {
        for state in T.allCases {
            // Everything below works on plain strings: the enum values
            // themselves are not `Sendable` and cannot cross into `#expect`.
            let label = state.displayName
            let caseName = state.rawValue
            let context = "\(T.self).\(caseName)"

            #expect(
                !label.isEmpty,
                "\(context) has an empty label",
                sourceLocation: sourceLocation
            )
            #expect(
                Self.strippingBrandNames(label).firstMatch(of: Self.camelCasePattern) == nil,
                "\(context) shows camelCase to the user: \(label)",
                sourceLocation: sourceLocation
            )
            // A single-word case name may legitimately equal its label
            // ("good" → "Good"). A multi-word identifier never may.
            if caseName.firstMatch(of: Self.camelCasePattern) != nil {
                #expect(
                    label.lowercased() != caseName.lowercased(),
                    "\(context) shows its raw value to the user: \(label)",
                    sourceLocation: sourceLocation
                )
            }
            #expect(
                label.first?.isUppercase == true,
                "\(context) should start with a capital: \(label)",
                sourceLocation: sourceLocation
            )
        }
    }

    @Test func permissionStatesReadAsEnglish() {
        assertUserFacing(PermissionAuthorizationState.self)
        assertUserFacing(LocationAuthorizationState.self)
        assertUserFacing(LocationAccuracyState.self)
        assertUserFacing(CapabilityAvailability.self)
    }

    @Test func qualityAndProvenanceStatesReadAsEnglish() {
        assertUserFacing(RouteQuality.self)
        assertUserFacing(MetricQuality.self)
        assertUserFacing(AltitudeSource.self)
        assertUserFacing(DistanceSource.self)
        assertUserFacing(StepSource.self)
    }

    @Test func healthStatesReadAsEnglish() {
        assertUserFacing(HealthAccessState.self)
        assertUserFacing(HealthEnrichmentStatus.self)
        assertUserFacing(HealthWorkoutExportStatus.self)
    }

    @Test func locationStatesKeepTheirDistinctMeanings() {
        // Regression guard for the two states that were previously collapsed
        // into the same "notDetermined" string replacement.
        #expect(LocationAuthorizationState.whenInUse.displayName == "Allowed while using the app")
        #expect(LocationAuthorizationState.always.displayName == "Always allowed")
        #expect(LocationAccuracyState.full.displayName == "Precise")
        #expect(LocationAccuracyState.reduced.displayName == "Approximate only")
        #expect(
            LocationAuthorizationState.notDetermined.displayName
                != LocationAuthorizationState.denied.displayName
        )
    }

    @Test func unavailableStatesNeverImplyAZeroMeasurement() {
        // §1 of the specification: absence must not read as a measured value.
        for label in [
            RouteQuality.unavailable.displayName,
            MetricQuality.unavailable.displayName,
            AltitudeSource.unavailable.displayName,
            DistanceSource.unavailable.displayName,
            StepSource.unavailable.displayName
        ] {
            #expect(!label.contains("0"))
            #expect(label.localizedCaseInsensitiveContains("no")
                || label.localizedCaseInsensitiveContains("not"))
        }
    }
}
