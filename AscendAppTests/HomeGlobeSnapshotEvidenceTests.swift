import CoreLocation
import MapKit
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Evidence for the globe under Home's sheet. MapKit annotations do not survive a
/// hierarchy capture, so the globe is photographed through `MKMapSnapshotter` at the
/// camera Home opens with, and the markers are composited at the points the snapshot
/// resolves for their coordinates, grouped by the same overlap rule the renderer
/// applies. The assertions are about geometry, not pixels: Home opens on the whole
/// globe, at the overview every reset lands on, whatever Today's Climb is.
@MainActor
struct HomeGlobeSnapshotEvidenceTests {
    @Test
    func homeOpensOnTheWholeGlobeAtTheOverview() async throws {
        let viewModel = GlobeViewModel(
            climbService: ClimbService(catalogRepository: StaticClimbCatalogRepository(climbs: [.preview, .previewComingSoon]))
        )
        viewModel.visibleClimbs = [.preview, .previewComingSoon]
        viewModel.dailyRecommendedClimb = .preview

        viewModel.prepareForHomeEntry()

        let camera = try #require(viewModel.cameraPosition.camera)
        let overview = GlobeViewModel.defaultOverviewCamera
        #expect(camera.distance == overview.distance)
        #expect(camera.centerCoordinate.latitude == overview.centerCoordinate.latitude)
        #expect(camera.centerCoordinate.longitude == overview.centerCoordinate.longitude)
        #expect(ClimbMapZoomBand(cameraDistance: camera.distance) == .world, "the whole globe is the world band")

        viewModel.mapCameraDidChange(
            latitude: camera.centerCoordinate.latitude,
            longitude: camera.centerCoordinate.longitude,
            distance: camera.distance
        )
        let scene = viewModel.mapScene
        #expect(scene.zoomBand == .world)
        #expect(scene.landmarks.map(\.id).contains(Climb.preview.id))
        #expect(!scene.showsNames, "names wait for country zoom")

        guard RenderedScreen.isPhotographing else { return }
        try await photographGlobe(camera: camera, scene: scene, named: "home-globe-overview")
    }

    @Test
    func namesFollowTheCameraBandAndTheOverlapRuleGroupsTheMarkers() {
        let viewModel = GlobeViewModel()
        viewModel.visibleClimbs = [Climb.preview, Climb.previewComingSoon]

        viewModel.mapCameraDidChange(latitude: 8, longitude: -76, distance: 28_000_000)
        #expect(viewModel.mapScene.zoomBand == .world)
        #expect(!viewModel.mapScene.showsNames)

        viewModel.mapCameraDidChange(latitude: Climb.preview.latitude, longitude: Climb.preview.longitude, distance: 4_000)
        #expect(viewModel.mapScene.zoomBand == .city)
        #expect(viewModel.mapScene.showsNames)

        // Grouping is a fact about screen points, not the band: on top of each other,
        // one pill; apart, two markers.
        let landmarks = viewModel.mapScene.landmarks
        let stacked = Dictionary(uniqueKeysWithValues: landmarks.map { ($0.id, CGPoint(x: 100, y: 100)) })
        #expect(ClimbMapClustering.layer(for: landmarks, points: stacked).clusters.count == 1)
        let apart = Dictionary(uniqueKeysWithValues: landmarks.enumerated().map { ($1.id, CGPoint(x: 100 + CGFloat($0) * 80, y: 100)) })
        #expect(ClimbMapClustering.layer(for: landmarks, points: apart).clusters.isEmpty)
    }

    // MARK: - Snapshot

    /// The globe at `camera` with `scene`'s markers drawn where the snapshot places them.
    /// Written to `ASCEND_EVIDENCE_DIR` only; the map tiles come from MapKit.
    private func photographGlobe(camera: MapCamera, scene: AscendMapScene, named name: String) async throws {
        let options = MKMapSnapshotter.Options()
        options.camera = MKMapCamera(
            lookingAtCenter: camera.centerCoordinate,
            fromDistance: camera.distance,
            pitch: camera.pitch,
            heading: camera.heading
        )
        options.mapType = .satelliteFlyover
        options.size = RenderedScreen.iPhone16ProSize
        options.scale = 2
        options.pointOfInterestFilter = .excludingAll

        let snapshot = try await MKMapSnapshotter(options: options).start()
        // The same grouping the renderer does from its MapProxy, here from the snapshot's projection.
        let points = Dictionary(uniqueKeysWithValues: scene.landmarks.map { ($0.id, snapshot.point(for: $0.climb.coordinate)) })
        let layer = ClimbMapClustering.layer(for: scene.landmarks, points: points)
        let renderer = UIGraphicsImageRenderer(size: snapshot.image.size)
        let image = renderer.image { _ in
            snapshot.image.draw(at: .zero)
            for landmark in layer.pins {
                let point = snapshot.point(for: landmark.climb.coordinate)
                let marker = ImageRenderer(content: ClimbMarkerView(
                    climb: landmark.climb,
                    completedClimberCount: landmark.completedClimberCount,
                    isCompleted: landmark.state == .completed,
                    isHighlighted: landmark.isHighlighted
                ))
                marker.scale = 2
                if let markerImage = marker.uiImage {
                    markerImage.draw(at: CGPoint(x: point.x - markerImage.size.width / 2, y: point.y - markerImage.size.height / 2))
                }
            }
            for cluster in layer.clusters {
                let point = snapshot.point(for: cluster.coordinate)
                let bubble = ImageRenderer(content: ClimbClusterBubbleView(cluster: cluster))
                bubble.scale = 2
                if let bubbleImage = bubble.uiImage {
                    bubbleImage.draw(at: CGPoint(x: point.x - bubbleImage.size.width / 2, y: point.y - bubbleImage.size.height / 2))
                }
            }
        }

        let todayPoint = snapshot.point(for: Climb.preview.coordinate)
        let frame = CGRect(origin: .zero, size: snapshot.image.size)
        #expect(frame.contains(todayPoint), "Today's Climb sits on the near side of the overview globe")

        try RenderedScreen.photograph(
            Image(uiImage: image).resizable().frame(width: image.size.width / 2, height: image.size.height / 2),
            named: name,
            scale: 2
        )
    }
}
