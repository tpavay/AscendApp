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
    /// Called once the descent reaches the landmark (used to fade the locator pin).
    var onArrived: () -> Void = {}

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
            autoOrbit: autoOrbit,
            onArrived: onArrived
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
        private weak var mapView: MKMapView?
        private var coordinate = CLLocationCoordinate2D()
        private var orbitDistance: CLLocationDistance = 1_400
        private var targetPitch: CGFloat = 74
        private var heading: CLLocationDirection = 0

        // Far enough that the whole globe is visible with margin.
        private let globeDistance: CLLocationDistance = 40_000_000
        // Beat to register the location (pin pulses) before the descent.
        private let holdDuration: CFTimeInterval = 1.3
        private let descentDuration: CFTimeInterval = 5.5
        private var startTimestamp: CFTimeInterval = 0
        private var autoOrbit = false
        private var didArrive = false
        private var onArrived: (() -> Void)?
        private var displayLink: CADisplayLink?

        func begin(
            mapView: MKMapView,
            coordinate: CLLocationCoordinate2D,
            orbitDistance: CLLocationDistance,
            targetPitch: CGFloat,
            autoOrbit: Bool,
            onArrived: @escaping () -> Void
        ) {
            self.mapView = mapView
            self.coordinate = coordinate
            self.orbitDistance = orbitDistance
            self.targetPitch = targetPitch
            self.autoOrbit = autoOrbit
            self.onArrived = onArrived

            // Open fully zoomed out on the globe.
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

            // 1) Hold on the globe so the user can see where in the world it is.
            if elapsed < holdDuration { return }

            let descentElapsed = elapsed - holdDuration
            if descentElapsed < descentDuration {
                // 2) Ease-IN descent: slow at the top, accelerating as it drops.
                let t = descentElapsed / descentDuration
                let e = t * t
                // Geometric interpolation keeps the zoom visually smooth.
                let distance = globeDistance * pow(orbitDistance / globeDistance, e)
                let pitch = e * targetPitch
                heading = e * 60
                setCamera(distance: distance, pitch: pitch)
                return
            }

            // 3) Arrived.
            if !didArrive {
                didArrive = true
                setCamera(distance: orbitDistance, pitch: targetPitch)
                onArrived?()
                if !autoOrbit { stop(); return }
            }
            heading += 0.16
            if heading >= 360 { heading -= 360 }
            setCamera(distance: orbitDistance, pitch: targetPitch)
        }

        private func setCamera(distance: CLLocationDistance, pitch: CGFloat) {
            mapView?.camera = MKMapCamera(
                lookingAtCenter: coordinate,
                fromDistance: distance,
                pitch: pitch,
                heading: heading
            )
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
    @State private var arrived = false
    @State private var pulse = false

    private let accent = Color(red: 0.706, green: 0.8, blue: 0)

    var body: some View {
        ZStack {
            ClimbFlyoverView(climb: climb, autoOrbit: true) {
                withAnimation(.easeOut(duration: 0.5)) { arrived = true }
            }
            .ignoresSafeArea()

            // Pulsing locator pin marking the spot while zoomed out / descending.
            if !arrived {
                ZStack {
                    Circle()
                        .stroke(accent.opacity(0.85), lineWidth: 2)
                        .frame(width: 44, height: 44)
                        .scaleEffect(pulse ? 2.6 : 1)
                        .opacity(pulse ? 0 : 0.9)
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(accent)
                        .shadow(color: .black.opacity(0.5), radius: 6, x: 0, y: 2)
                }
                .allowsHitTesting(false)
                .transition(.opacity)
                .onAppear {
                    withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) {
                        pulse = true
                    }
                }
            }

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
