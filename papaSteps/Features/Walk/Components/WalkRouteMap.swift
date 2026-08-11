import MapKit
import SwiftUI

struct WalkRouteMap: View {
    let segments: [[WalkCoordinate]]
    let currentCoordinate: WalkCoordinate?
    var showsEndpointMarkers = false
    var followsCurrentLocation = false

    @State private var position: MapCameraPosition = .automatic
    @State private var isFollowing = true

    private var coordinates: [WalkCoordinate] {
        segments.flatMap { $0 }
    }

    var body: some View {
        Group {
            if coordinates.isEmpty, currentCoordinate == nil {
                ContentUnavailableView(
                    "Route Unavailable",
                    systemImage: "location.slash",
                    description: Text("A route appears after reliable precise-location points are accepted.")
                )
                .background(.quaternary)
            } else {
                Map(position: $position, interactionModes: .all) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        if segment.count > 1 {
                            MapPolyline(coordinates: segment.map(\.clCoordinate))
                                .stroke(.blue, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        }
                    }

                    if showsEndpointMarkers, let first = coordinates.first {
                        Marker("Start", systemImage: "figure.walk.departure", coordinate: first.clCoordinate)
                            .tint(.green)
                    }
                    if showsEndpointMarkers, let last = coordinates.last {
                        Marker("Finish", systemImage: "flag.checkered", coordinate: last.clCoordinate)
                            .tint(.red)
                    } else if let currentCoordinate {
                        Marker(
                            "Current position",
                            systemImage: "figure.walk",
                            coordinate: currentCoordinate.clCoordinate
                        )
                        .tint(.blue)
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .mapControls {
                    MapCompass()
                    MapScaleView()
                }
                .overlay(alignment: .topTrailing) {
                    if followsCurrentLocation {
                        Button {
                            isFollowing.toggle()
                            updateCamera()
                        } label: {
                            Label(
                                isFollowing ? "Following" : "Follow Route",
                                systemImage: isFollowing ? "location.fill" : "location"
                            )
                        }
                        .buttonStyle(.bordered)
                        .labelStyle(.iconOnly)
                        .background(.regularMaterial, in: .circle)
                        .padding(8)
                    }
                }
                .onChange(of: coordinates.count, initial: true) { _, _ in
                    guard !followsCurrentLocation || isFollowing else { return }
                    updateCamera()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(mapAccessibilityLabel)
            }
        }
        .frame(height: followsCurrentLocation ? 230 : 280)
        .clipShape(.rect(cornerRadius: 16))
        .accessibilityIdentifier("walk.route.map")
    }

    private var mapAccessibilityLabel: String {
        guard !coordinates.isEmpty else { return "Walking route unavailable" }
        return "Walking route map with \(coordinates.count) accepted points"
    }

    private func updateCamera() {
        let framedCoordinates = coordinates.isEmpty
            ? [currentCoordinate].compactMap { $0 }
            : coordinates
        guard let first = framedCoordinates.first else { return }

        if followsCurrentLocation, let currentCoordinate, isFollowing {
            position = .region(
                MKCoordinateRegion(
                    center: currentCoordinate.clCoordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
                )
            )
            return
        }

        var rect = MKMapRect(origin: MKMapPoint(first.clCoordinate), size: .init())
        for coordinate in framedCoordinates.dropFirst() {
            let point = MKMapPoint(coordinate.clCoordinate)
            rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
        }
        if rect.width == 0, rect.height == 0 {
            position = .region(
                MKCoordinateRegion(
                    center: first.clCoordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
                )
            )
        } else {
            position = .rect(rect.insetBy(dx: -max(rect.width * 0.15, 80), dy: -max(rect.height * 0.15, 80)))
        }
    }
}

private extension WalkCoordinate {
    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
