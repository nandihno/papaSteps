import SwiftUI

/// A miniature of a walk's route for list rows.
///
/// Drawn as a vector path from downsampled coordinates rather than a map
/// snapshot: a list of two hundred walks would otherwise fetch two hundred map
/// images. It shows the shape of the walk, which is what a row needs — the real
/// map is one tap away.
struct RouteThumbnail: View {
    let coordinates: [WalkCoordinate]
    var size: CGFloat = 68

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(Color.surfaceSunken)

            if coordinates.count > 1 {
                RoutePath(coordinates: coordinates)
                    .stroke(
                        Color.brandGreen,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                    )
                    .padding(Spacing.xs)
            } else {
                Image(systemName: WalkSymbol.locationOff)
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .strokeBorder(Color.strokeHairline, lineWidth: 1)
        )
        // The row states the walk's metrics in words; the shape adds nothing a
        // screen reader can use.
        .accessibilityHidden(true)
    }
}

/// Normalizes latitude/longitude into the available rectangle, preserving the
/// route's aspect ratio so a straight walk does not render as a diagonal that
/// fills the box.
private struct RoutePath: Shape {
    let coordinates: [WalkCoordinate]

    func path(in rect: CGRect) -> Path {
        guard coordinates.count > 1 else { return Path() }

        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        guard let minLatitude = latitudes.min(),
              let maxLatitude = latitudes.max(),
              let minLongitude = longitudes.min(),
              let maxLongitude = longitudes.max() else {
            return Path()
        }

        // Longitude degrees shrink with latitude; without this a walk looks
        // stretched east-west.
        let latitudeSpan = max(maxLatitude - minLatitude, 0.000_01)
        let longitudeScale = cos(minLatitude * .pi / 180)
        let longitudeSpan = max((maxLongitude - minLongitude) * longitudeScale, 0.000_01)

        let scale = min(rect.width / longitudeSpan, rect.height / latitudeSpan)
        let drawnWidth = longitudeSpan * scale
        let drawnHeight = latitudeSpan * scale
        let originX = rect.minX + (rect.width - drawnWidth) / 2
        let originY = rect.minY + (rect.height - drawnHeight) / 2

        func point(for coordinate: WalkCoordinate) -> CGPoint {
            let x = (coordinate.longitude - minLongitude) * longitudeScale * scale
            // Latitude increases northward; screen y increases downward.
            let y = drawnHeight - (coordinate.latitude - minLatitude) * scale
            return CGPoint(x: originX + x, y: originY + y)
        }

        var path = Path()
        path.move(to: point(for: coordinates[0]))
        for coordinate in coordinates.dropFirst() {
            path.addLine(to: point(for: coordinate))
        }
        return path
    }
}

/// A screen with nothing in it yet: one symbol, one sentence, one way forward.
struct EmptyStateView<Actions: View>: View {
    let title: String
    let message: String
    let systemImage: String
    @ViewBuilder var actions: Actions

    @ScaledMetric(relativeTo: .largeTitle) private var symbolSize: CGFloat = 48

    var body: some View {
        VStack(spacing: Spacing.medium) {
            Image(systemName: systemImage)
                .font(.system(size: symbolSize))
                .foregroundStyle(Color.brandGreenInk)
                .accessibilityHidden(true)

            VStack(spacing: Spacing.xs) {
                Text(title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }

            actions
        }
        .frame(maxWidth: 420)
        .padding(Spacing.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(title: String, message: String, systemImage: String) {
        self.init(title: title, message: message, systemImage: systemImage) {
            EmptyView()
        }
    }
}
