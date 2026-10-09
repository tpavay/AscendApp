import Foundation
import RealityKit
import simd

/// The stone trail post standing at every hundred steps: a square shaft set in the ground just
/// outside the right kerb, with the step count on a sign hung on its climber-facing side.
///
/// The whole post is turned in toward the climber as one piece, so in the post's own frame the
/// climber is always toward +z and the sign is simply the nearest thing to them: the shaft ends
/// at `shaftHalfWidth`, the board starts beyond it, and the face sits on the board's front. A
/// sign that merely overlapped the shaft put the post through the number (captain, 2026-10-09),
/// so `signClearance` is the contract every build keeps, pinned by
/// `AscendMountainTrailPostTests`.
enum MountainTrailPost {
    /// How far the shaft stands outside the right kerb.
    static let kerbClearance: Float = 0.3
    static let shaftWidth: Float = 0.2
    /// The shaft reaches a metre below the tread so it stands in the ground on any slope.
    static let shaftBottom: Float = -1
    static let shaftTop: Float = 1.15
    /// How far the post turns in toward the climber, about the vertical.
    static let yaw: Float = -0.35

    static let boardSize = SIMD3<Float>(0.86, 0.46, 0.07)
    static let faceSize = SIMD2<Float>(0.8, 0.4)
    /// Where the sign's centre hangs, at the top of the shaft so the shaft disappears behind it.
    static let signHeight: Float = 1.11
    /// Daylight between the shaft's front and the board's back, and between the board's front and
    /// the face: enough that no two surfaces fight for the same pixels.
    static let signClearance: Float = 0.005

    static var shaftHalfWidth: Float { shaftWidth / 2 }
    static var shaftCentre: SIMD3<Float> { [0, (shaftTop + shaftBottom) / 2, 0] }
    static var shaftSize: SIMD3<Float> { [shaftWidth, shaftTop - shaftBottom, shaftWidth] }
    /// The board's centre, its back just clear of the shaft's front.
    static var boardCentre: SIMD3<Float> { [0, signHeight, shaftHalfWidth + signClearance + boardSize.z / 2] }
    /// The face's centre, just clear of the board's front.
    static var faceCentre: SIMD3<Float> { [0, signHeight, boardCentre.z + boardSize.z / 2 + signClearance] }

    /// Where the post's mount stands in the marker's frame: at the stair's right kerb, turned in.
    static var mountPosition: SIMD3<Float> {
        [Float(MountainStairGeometry.width / 2 + MountainChunkGeometry.kerbWidth) + kerbClearance, 0, 0]
    }

    static var mountOrientation: simd_quatf { simd_quatf(angle: yaw, axis: [0, 1, 0]) }

    static let mountName = "trail-post"
    static let shaftName = "trail-post-shaft"
    static let boardName = "trail-post-board"
    static let faceName = "trail-post-face"

    /// The post for `marker`, in the marker's frame: x across the stairs, y up, z toward the
    /// climber coming up behind it.
    @MainActor
    static func make(for marker: MountainMarker, stone: any Material) -> Entity {
        let post = Entity()
        let mount = Entity()
        mount.name = mountName
        mount.position = mountPosition
        mount.orientation = mountOrientation
        post.addChild(mount)

        let shaft = ModelEntity(mesh: .generateBox(size: shaftSize, cornerRadius: 0.03), materials: [stone])
        shaft.name = shaftName
        shaft.position = shaftCentre
        mount.addChild(shaft)

        let board = ModelEntity(mesh: .generateBox(size: boardSize, cornerRadius: 0.03), materials: [stone])
        board.name = boardName
        board.position = boardCentre
        mount.addChild(board)

        let face = MountainPlaque.face(width: faceSize.x, height: faceSize.y, cornerRadius: 0.04, title: marker.title, subtitle: marker.subtitle)
        face.name = faceName
        face.position = faceCentre
        mount.addChild(face)
        return post
    }
}
