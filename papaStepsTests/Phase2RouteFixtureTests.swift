import Foundation
import Testing
@testable import papaSteps

struct Phase2RouteFixtureTests {
    @Test
    func gpxFixtureProducesKilometreRouteWithinTolerance() async throws {
        let coordinates = try loadCoordinates(
            resource: "melbourne-kilometre-route",
            extension: "gpx"
        )
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var configuration = TrackingConfiguration.live
        configuration.maximumRouteGap = 90
        let engine = WalkMetricsEngine(configuration: configuration)
        _ = await engine.start(
            id: UUID(),
            at: start,
            timeZoneIdentifier: "Australia/Melbourne"
        )

        for (index, coordinate) in coordinates.enumerated() {
            let date = start.addingTimeInterval(Double(index + 1) * 90)
            _ = await engine.ingestLocation(
                WalkLocationSample(
                    coordinate: coordinate,
                    timestamp: date,
                    altitude: 28,
                    horizontalAccuracy: 6,
                    verticalAccuracy: 5,
                    speed: 1.4,
                    speedAccuracy: 0.3,
                    course: 0,
                    courseAccuracy: 5,
                    accuracyAuthorization: .full
                ),
                receivedAt: date
            )
        }

        let end = start.addingTimeInterval(Double(coordinates.count + 1) * 90)
        let record = try await engine.finalize(at: end)
        let routeDistance = try #require(record.routeDistance)
        #expect(abs(routeDistance - 1_000) < 40)
        #expect(record.routeQuality == .good)
        #expect(record.trackPoints.count == coordinates.count)
        #expect(record.trackPoints.first?.startsNewSegment == true)
    }

    private func loadCoordinates(
        resource: String,
        extension fileExtension: String
    ) throws -> [WalkCoordinate] {
        let bundle = Bundle(for: FixtureBundleAnchor.self)
        let url = try #require(
            bundle.url(
                forResource: resource,
                withExtension: fileExtension,
                subdirectory: "Fixtures"
            ) ?? bundle.url(forResource: resource, withExtension: fileExtension)
        )
        let parser = XMLParser(contentsOf: url)
        let delegate = GPXCoordinateParser()
        parser?.delegate = delegate
        #expect(parser?.parse() == true)
        return delegate.coordinates
    }
}

private final class FixtureBundleAnchor: NSObject {}

private final class GPXCoordinateParser: NSObject, XMLParserDelegate {
    private(set) var coordinates: [WalkCoordinate] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName == "wpt",
              let latitudeText = attributeDict["lat"],
              let longitudeText = attributeDict["lon"],
              let latitude = Double(latitudeText),
              let longitude = Double(longitudeText) else {
            return
        }
        coordinates.append(
            WalkCoordinate(latitude: latitude, longitude: longitude)
        )
    }
}
