import CoreLocation
import MapKit
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Evidence for the globe under Home's sheet. MapKit annotations do not survive a
/// hierarchy capture, so the globe is photographed through `MKMapSnapshotter` at the
/// camera Home opens with, and the pins are composited at the points the snapshot
/// resolves for their coordinates. The assertions are about geometry, not pixels:
/// Home opens centred on Today's Climb at continent altitude, and the pin layer at
/// that altitude is pins, not counts.
@MainActor
struct HomeGlobeSnapshotEvidenceTests {
    @Test
    func homeOpensCentredOnTodaysClimbAtContinentAltitude() async throws {
        let viewModel = GlobeViewModel(
            climbService: ClimbService(catalogRepository: StaticClimbCatalogRepository(climbs: [.preview, .previewComingSoon]))
        )
        viewModel.visibleClimbs = [.preview, .previewComingSoon]
        viewModel.dailyRecommendedClimb = .preview

        viewModel.prepareForHomeEntry()

        let camera = try #require(viewModel.cameraPosition.camera)
        #expect(camera.distance == ClimbMapZoomBand.homeEntryCameraDistance)
        #expect(abs(camera.centerCoordinate.latitude - Climb.preview.latitude) < 0.001)
        #expect(abs(camera.centerCoordinate.longitude - Climb.preview.longitude) < 0.001)

        viewModel.mapCameraDidChange(
            latitude: camera.centerCoordinate.latitude,
            longitude: camera.centerCoordinate.longitude,
            distance: camera.distance
        )
        let scene = viewModel.mapScene
        #expect(scene.zoomBand == .continent)
        #expect(scene.layer.clusters.isEmpty, "continent altitude draws pins, not counts")
        #expect(scene.layer.pins.map(\.id).contains(Climb.preview.id))
        #expect(!scene.showsNames, "names wait for country zoom")

        guard RenderedScreen.isPhotographing else { return }
        try await photographGlobe(camera: camera, scene: scene, named: "home-globe-continent")
    }

    @Test
    func worldZoomGathersPinsIntoCountsAndCityZoomNamesThem() {
        let viewModel = GlobeViewModel()
        let neighbours = [Climb.preview, Climb.previewComingSoon]
        viewModel.visibleClimbs = neighbours

        viewModel.mapCameraDidChange(latitude: 8, longitude: -76, distance: 28_000_000)
        #expect(viewModel.mapScene.zoomBand == .world)
        let worldLayer = viewModel.mapScene.layer
        #expect(worldLayer.pins.count + worldLayer.clusters.reduce(0) { $0 + $1.count } == neighbours.count)

        viewModel.mapCameraDidChange(latitude: Climb.preview.latitude, longitude: Climb.preview.longitude, distance: 4_000)
        #expect(viewModel.mapScene.zoomBand == .city)
        #expect(viewModel.mapScene.showsNames)
        #expect(viewModel.mapScene.layer.clusters.isEmpty)
    }

    // MARK: - Snapshot

    /// The globe at `camera` with `scene`'s pins drawn where the snapshot places them.
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
        let renderer = UIGraphicsImageRenderer(size: snapshot.image.size)
        let image = renderer.image { _ in
            snapshot.image.draw(at: .zero)
            for landmark in scene.layer.pins {
                let point = snapshot.point(for: landmark.climb.coordinate)
                let pin = ImageRenderer(content: ClimbPinView(
                    climb: landmark.climb,
                    isCompleted: landmark.state == .completed,
                    isHighlighted: landmark.isHighlighted
                ))
                pin.scale = 2
                if let pinImage = pin.uiImage {
                    pinImage.draw(at: CGPoint(x: point.x - pinImage.size.width / 2, y: point.y - pinImage.size.height))
                }
            }
            for cluster in scene.layer.clusters {
                let point = snapshot.point(for: cluster.coordinate)
                let bubble = ImageRenderer(content: ClimbClusterBubbleView(cluster: cluster))
                bubble.scale = 2
                if let bubbleImage = bubble.uiImage {
                    bubbleImage.draw(at: CGPoint(x: point.x - bubbleImage.size.width / 2, y: point.y - bubbleImage.size.height / 2))
                }
            }
        }

        let todayPoint = snapshot.point(for: Climb.preview.coordinate)
        let centre = CGPoint(x: snapshot.image.size.width / 2, y: snapshot.image.size.height / 2)
        #expect(abs(todayPoint.x - centre.x) < 4)
        #expect(abs(todayPoint.y - centre.y) < 4)

        try RenderedScreen.photograph(
            Image(uiImage: image).resizable().frame(width: image.size.width / 2, height: image.size.height / 2),
            named: name,
            scale: 2
        )
    }
}
