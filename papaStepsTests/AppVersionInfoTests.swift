import Foundation
import Testing
@testable import papaSteps

struct AppVersionInfoTests {
    private final class StubBundle: Bundle, @unchecked Sendable {
        private let values: [String: Any]

        init(values: [String: Any]) {
            self.values = values
            super.init()
        }

        override func object(forInfoDictionaryKey key: String) -> Any? {
            values[key]
        }
    }

    @Test
    func combinesVersionAndBuildForDisplay() {
        let info = AppVersionInfo(version: "1.04", build: "3")

        #expect(info.displayValue == "1.04 (3)")
    }

    @Test
    func readsVersionAndBuildFromTheBundle() {
        let bundle = StubBundle(values: [
            "CFBundleShortVersionString": "2.1",
            "CFBundleVersion": "17"
        ])

        let info = AppVersionInfo(bundle: bundle)

        #expect(info.version == "2.1")
        #expect(info.build == "17")
        #expect(info.displayValue == "2.1 (17)")
    }

    @Test
    func missingOrBlankKeysFallBackToAPlaceholderRatherThanAFakeVersion() {
        let bundle = StubBundle(values: ["CFBundleShortVersionString": "   "])

        let info = AppVersionInfo(bundle: bundle)

        #expect(info.version == AppVersionInfo.unknownValue)
        #expect(info.build == AppVersionInfo.unknownValue)
    }

    @Test
    func theRealAppBundleExposesBothValues() {
        let info = AppVersionInfo(bundle: Bundle(for: StubBundle.self))

        #expect(info.version != "")
        #expect(info.build != "")
    }
}
