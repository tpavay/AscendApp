import MapKit
import SwiftUI

/// A cinematic in-app landmark sequence: opens on a zoomed-out globe for world
/// context, swoops down to the climb's real-world landmark, then orbits it
/// using Apple's satellite-flyover 3D data.
///
/// In-app / ephemeral ONLY — Apple Maps imagery must NOT be recorded or
/// exported per MapKit terms. This is for live viewing inside the app, never a
/// shareable video. A shareable "climb simulation" must use owned imagery.
struct ClimbFlyoverView: UIViewRepresentable {
    let climb: Climb
    /// When false (default), the camera flies in and holds a centered static
    /// shot. When true, it slowly orbits after arriving.
    var autoOrbit: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.mapType = .satelliteFlyover
        map.showsCompass = false
        map.showsScale = false
        map.pointOfInterestFilter = .excludingAll
        map.isUserInteractionEnabled = true

        // Observe pinch/drag so the first user touch stops the orbit and hands
        // over free control (these recognize simultaneously with the map's own
        // gestures, so they only observe — they don't consume the touch).
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.userTookControl))
        pan.delegate = context.coordinator
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.userTookControl))
        pinch.delegate = context.coordinator
        map.addGestureRecognizer(pan)
        map.addGestureRecognizer(pinch)

        context.coordinator.begin(
            mapView: map,
            coordinate: climb.coordinate,
            orbitDistance: ClimbCameraFraming.distance(for: climb),
            targetPitch: ClimbCameraFraming.pitch(for: climb),
            autoOrbit: autoOrbit
        )
        return map
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {}

    static func dismantleUIView(_ uiView: MKMapView, coordinator: Coordinator) {
        coordinator.stop()
    }

    // MARK: - Coordinator (frame-driven descent + orbit)

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private enum Phase { case descending, orbiting }

        private weak var mapView: MKMapView?
        private var coordinate = CLLocationCoordinate2D()
        private var orbitDistance: CLLocationDistance = 1_400
        private var targetPitch: CGFloat = 74
        private var heading: CLLocationDirection = 0

        private let globeDistance: CLLocationDistance = 16_000_000
        private let descentDuration: CFTimeInterval = 5.0
        private var startTimestamp: CFTimeInterval = 0
        private var phase: Phase = .descending
        private var autoOrbit = false
        private var displayLink: CADisplayLink?

        func begin(
            mapView: MKMapView,
            coordinate: CLLocationCoordinate2D,
            orbitDistance: CLLocationDistance,
            targetPitch: CGFloat,
            autoOrbit: Bool
        ) {
            self.mapView = mapView
            self.coordinate = coordinate
            self.orbitDistance = orbitDistance
            self.targetPitch = targetPitch
            self.autoOrbit = autoOrbit

            // Open on the globe.
            mapView.camera = MKMapCamera(
                lookingAtCenter: coordinate,
                fromDistance: globeDistance,
                pitch: 0,
                heading: 0
            )

            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        @objc private func tick(_ link: CADisplayLink) {
            if startTimestamp == 0 { startTimestamp = link.timestamp }
            let elapsed = link.timestamp - startTimestamp

            switch phase {
            case .descending:
                let t = min(elapsed / descentDuration, 1)
                let e = Self.easeInOut(t)
                // Geometric interpolation so the zoom feels even (Google-Earth swoop).
                let distance = globeDistance * pow(orbitDistance / globeDistance, e)
                let pitch = e * targetPitch
                heading = e * 80 // gentle quarter-turn on the way down
                setCamera(distance: distance, pitch: pitch)
                if t >= 1 {
                    if autoOrbit {
                        phase = .orbiting
                    } else {
                        stop() // hold the centered static shot
                    }
                }

            case .orbiting:
                heading += 0.16
                if heading >= 360 { heading -= 360 }
                setCamera(distance: orbitDistance, pitch: targetPitch)
            }
        }

        private func setCamera(distance: CLLocationDistance, pitch: CGFloat) {
            mapView?.camera = MKMapCamera(
                lookingAtCenter: coordinate,
                fromDistance: distance,
                pitch: pitch,
                heading: heading
            )
        }

        private static func easeInOut(_ t: Double) -> Double {
            t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
        }

        func stop() {
            displayLink?.invalidate()
            displayLink = nil
        }

        /// First user touch (pinch/drag) ends the auto-motion and leaves the
        /// map fully under user control.
        @objc func userTookControl() {
            stop()
        }

        nonisolated func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

/// Full-screen flyover presentation with a close control and a climb label.
struct ClimbFlyoverScreen: View {
    let climb: Climb
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            ClimbFlyoverView(climb: climb, autoOrbit: true)
                .ignoresSafeArea()

            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(.black.opacity(0.4)))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Spacer()

                VStack(spacing: 4) {
                    Text(climb.name)
                        .font(.montserratBold(size: 26))
                        .foregroundStyle(.white)
                    Text(climb.displayLocation.uppercased())
                        .font(.montserratSemiBold(size: 12))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 40)
                .padding(.top, 24)
                .background(
                    LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea()
                )
            }
        }
        .background(Color.black.ignoresSafeArea())
    }
}
