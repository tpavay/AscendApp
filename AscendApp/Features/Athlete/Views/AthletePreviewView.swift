import RealityKit
import SwiftUI

/// A climber's athlete standing on a lit stage, turning slowly so every side of the look shows.
/// The editor, the onboarding step and the Profile card all draw it; a change of look is worn as
/// soon as its body has loaded, and until then the previous one keeps standing.
struct AthletePreviewView: View {
    /// How much of the athlete the stage frames.
    enum Framing {
        /// Head to trainers: the editor and onboarding.
        case fullBody
        /// Head and shoulders to the waist, for a small card.
        case portrait
    }

    let look: AthleteLook
    /// Whether the athlete turns; still, they stand three-quarters on.
    var turns = true
    var framing = Framing.fullBody

    @State private var stage = AthletePreviewStage()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let stage = stage
        RealityView { content in
            stage.install(in: &content, framing: framing)
        } placeholder: {
            Color.clear
        }
        .task(id: look) {
            await stage.show(look)
        }
        .onChange(of: turns && !reduceMotion, initial: true) { _, turning in
            stage.isTurning = turning
        }
        .accessibilityElement()
        .accessibilityLabel(AthleteLookDescription.sentence(for: look))
    }
}

/// Plain words for a look, for VoiceOver: the athlete itself is a picture.
enum AthleteLookDescription {
    static func sentence(for look: AthleteLook) -> String {
        "Your athlete: body \(look.body.title), \(look.size.title.lowercased()) size, \(look.muscle.title.lowercased()) muscle, "
            + "\(look.hairStyle.title.lowercased()) \(hairColorName(look.hairColor)) hair, "
            + "\(look.top.rawValue) tank, \(look.bottom.rawValue) shorts, \(look.shoes.rawValue) shoes."
    }

    static func hairColorName(_ color: AthleteLook.HairColor) -> String {
        switch color {
        case .black: "black"
        case .darkBrown: "dark brown"
        case .brown: "brown"
        case .blond: "blond"
        case .red: "red"
        case .grey: "grey"
        }
    }
}

/// The entities behind `AthletePreviewView`: a camera framing a standing athlete, a key and a
/// rim light, and the turntable the athlete stands on.
@MainActor
final class AthletePreviewStage {
    var isTurning = false

    private let root = Entity()
    private let turntable = Entity()
    private let camera = PerspectiveCamera()
    private var rig: MountainAthleteRig?
    private var shown: AthleteLook?
    private var updates: EventSubscription?
    private let rigs: MountainRigFactory

    /// Three-quarters on, the way the athlete stands when it does not turn.
    static let restingAngle: Float = -0.45
    /// One turn every fourteen seconds.
    static let turnRadiansPerSecond: Float = 2 * .pi / 14

    init(rigs: MountainRigFactory = .shared) {
        self.rigs = rigs
        turntable.orientation = simd_quatf(angle: Self.restingAngle, axis: [0, 1, 0])
        root.addChild(turntable)

        camera.camera.fieldOfViewInDegrees = 30
        root.addChild(camera)

        let key = DirectionalLight()
        key.light.intensity = 1_700
        key.look(at: .zero, from: [1.6, 3, 2.6], relativeTo: nil)
        root.addChild(key)

        let rim = DirectionalLight()
        rim.light.intensity = 1_100
        rim.light.color = UIColor(red: 0.8, green: 0.95, blue: 0.62, alpha: 1)
        rim.look(at: [0, 1, 0], from: [-2, 2.2, -2.6], relativeTo: nil)
        root.addChild(rim)
    }

    func install(in content: inout RealityViewCameraContent, framing: AthletePreviewView.Framing) {
        self.framing = framing
        frame(raisedOverhead: shown?.carry?.carry == .overhead)
        content.camera = .virtual
        content.renderingEffects.motionBlur = .disabled
        content.renderingEffects.depthOfField = .disabled
        content.renderingEffects.cameraGrain = .disabled
        content.add(root)
        updates?.cancel()
        updates = content.subscribe(to: SceneEvents.Update.self, on: nil, componentType: nil) { [weak self] event in
            self?.turn(by: Float(event.deltaTime))
        }
    }

    func show(_ look: AthleteLook) async {
        guard look != shown,
              let made = try? await rigs.rig(.init(look: look, style: .athlete(look), label: "", castsLight: true)) else { return }
        made.stand()
        frame(raisedOverhead: look.carry?.carry == .overhead)
        rig?.root.removeFromParent()
        turntable.addChild(made.root)
        rig = made
        shown = look
    }

    private var framing = AthletePreviewView.Framing.fullBody

    /// Aims the camera at the athlete, pulled back and up when they press a giant overhead so
    /// the whole of it stays in frame.
    private func frame(raisedOverhead: Bool) {
        switch (framing, raisedOverhead) {
        case (.fullBody, false):
            camera.look(at: [0, 0.93, 0], from: [0, 1.05, 4.1], relativeTo: nil)
        case (.fullBody, true):
            camera.look(at: [0, 1.22, 0], from: [0, 1.36, 5.6], relativeTo: nil)
        case (.portrait, false):
            camera.look(at: [0, 1.36, 0], from: [0, 1.46, 2.1], relativeTo: nil)
        case (.portrait, true):
            camera.look(at: [0, 1.75, 0], from: [0, 1.85, 3.2], relativeTo: nil)
        }
    }

    private func turn(by seconds: Float) {
        guard isTurning, seconds > 0 else { return }
        turntable.orientation = simd_quatf(angle: seconds * Self.turnRadiansPerSecond, axis: [0, 1, 0]) * turntable.orientation
    }
}
