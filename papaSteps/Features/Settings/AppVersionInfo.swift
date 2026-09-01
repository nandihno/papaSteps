import Foundation

/// The app's marketing version and build number, as shown in Settings.
///
/// Reading these from the bundle rather than hard-coding them means the value
/// on screen always matches the binary the user is actually running — which is
/// the whole point when someone reports a bug against "the latest version".
struct AppVersionInfo: Equatable, Sendable {
    /// Shown when a key is missing from the bundle, which happens in some test
    /// and preview contexts. Better an honest placeholder than a fake "1.0".
    static let unknownValue = "—"

    let version: String
    let build: String

    /// e.g. `1.04 (3)`.
    var displayValue: String {
        "\(version) (\(build))"
    }

    init(version: String, build: String) {
        self.version = version
        self.build = build
    }

    init(bundle: Bundle = .main) {
        func string(for key: String) -> String {
            guard let value = bundle.object(forInfoDictionaryKey: key) as? String,
                  !value.trimmingCharacters(in: .whitespaces).isEmpty else {
                return Self.unknownValue
            }
            return value
        }

        self.init(
            version: string(for: "CFBundleShortVersionString"),
            build: string(for: "CFBundleVersion")
        )
    }
}
