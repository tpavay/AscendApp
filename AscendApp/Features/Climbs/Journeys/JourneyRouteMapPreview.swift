#if DEBUG
import CoreLocation
import MapKit
import SwiftUI

struct JourneyRouteMapPreview: View {
    let journey: JourneyPrototype
    let completedClimbIds: Set<String>
    let selectedClimbId: String?
    let onSelectClimb: (Climb) -> Void

    var body: some View {
        Map(
            position: .constant(.region(mapRegion)),
            interactionModes: [.pan, .zoom, .rotate, .pitch]
        ) {
            routeBaseLine
            completedLine
            currentLine
            markers
        }
        .mapStyle(.imagery(elevation: .realistic))
        .mapControls {}
        .frame(height: 292)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .topLeading) {
            mapLabel
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        }
    }

    private var mapRegion: MKCoordinateRegion {
        MKCoordinateRegion.ascendJourneyRegion(for: journey.coordinates)
    }

    @MapContentBuilder
    private var routeBaseLine: some MapContent {
        if journey.coordinates.count > 1 {
            MapPolyline(coordinates: journey.coordinates)
                .stroke(.white.opacity(0.34), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
    }

    @MapContentBuilder
    private var completedLine: some MapContent {
        if completedRouteCoordinates.count > 1 {
            MapPolyline(coordinates: completedRouteCoordinates)
                .stroke(journey.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
        }
    }

    @MapContentBuilder
    private var currentLine: some MapContent {
        if currentRouteCoordinates.count > 1 {
            MapPolyline(coordinates: currentRouteCoordinates)
                .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round, dash: [8, 8]))
        }
    }

    @MapContentBuilder
    private var markers: some MapContent {
        ForEach(journey.steps(in: completedClimbIds)) { step in
            Annotation("", coordinate: step.climb.coordinate, anchor: .center) {
                Button {
                    onSelectClimb(step.climb)
                } label: {
                    JourneyRouteMarker(
                        step: step,
                        accent: journey.accent,
                        isSelected: selectedClimbId == step.climb.id
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(step.index + 1). \(step.climb.name), \(step.status.label)")
            }
        }
    }

    private var completedRouteCoordinates: [CLLocationCoordinate2D] {
        let completedCount = journey.completedPrefixCount(in: completedClimbIds)
        guard completedCount > 1 else { return [] }
        return Array(journey.coordinates.prefix(completedCount))
    }

    private var currentRouteCoordinates: [CLLocationCoordinate2D] {
        let currentIndex = journey.completedPrefixCount(in: completedClimbIds)
        guard currentIndex < journey.coordinates.count - 1 else { return [] }
        return Array(journey.coordinates[currentIndex ... currentIndex + 1])
    }

    private var mapLabel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(journey.title.uppercased())
                .font(.montserratBold(size: 11))
                .tracking(1.6)
                .foregroundStyle(journey.accent)

            Text("\(journey.progressText(in: completedClimbIds)) claimed")
                .font(.montserratSemiBold(size: 13))
                .foregroundStyle(.white.opacity(0.86))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(12)
    }
}

private extension MKCoordinateRegion {
    static func ascendJourneyRegion(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard let first = coordinates.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 18, longitude: 8),
                span: MKCoordinateSpan(latitudeDelta: 86, longitudeDelta: 150)
            )
        }

        var minLatitude = first.latitude
        var maxLatitude = first.latitude
        var minLongitude = first.longitude
        var maxLongitude = first.longitude

        for coordinate in coordinates.dropFirst() {
            minLatitude = min(minLatitude, coordinate.latitude)
            maxLatitude = max(maxLatitude, coordinate.latitude)
            minLongitude = min(minLongitude, coordinate.longitude)
            maxLongitude = max(maxLongitude, coordinate.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )
        let latitudeDelta = min(max((maxLatitude - minLatitude) * 1.55, 8), 120)
        let longitudeDelta = min(max((maxLongitude - minLongitude) * 1.55, 14), 320)

        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        )
    }
}
#endif
