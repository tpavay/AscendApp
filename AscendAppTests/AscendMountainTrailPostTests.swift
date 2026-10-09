import Foundation
import RealityKit
import simd
import Testing
import UIKit

@testable import AscendApp

/// The trail post's step count has to be readable from the climber's camera. Every post up to
/// 1.2.3 hung its sign through the shaft, so the shaft stood in front of the number from the
/// bottom of the sign to its own top (captain, 2026-10-09). These pin the shape that fixes it.
@MainActor
struct AscendMountainTrailPostTests {
    private static let marker = MountainMarker(id: "post_100", step: 100, kind: .post, design: "post_stone", title: "100", subtitle: nil)

    /// In the post's own frame the climber is toward +z. The shaft ends at its half width, the
    /// board starts beyond it, and the face sits beyond the board: nothing of the post reaches
    /// the number.
    @Test
    func theSignHangsClearInFrontOfTheShaft() {
        let shaftFront = MountainTrailPost.shaftCentre.z + MountainTrailPost.shaftSize.z / 2
        let boardBack = MountainTrailPost.boardCentre.z - MountainTrailPost.boardSize.z / 2
        let boardFront = MountainTrailPost.boardCentre.z + MountainTrailPost.boardSize.z / 2

        #expect(shaftFront == MountainTrailPost.shaftHalfWidth)
        #expect(boardBack >= shaftFront + MountainTrailPost.signClearance, "the board's back clears the shaft's front")
        #expect(MountainTrailPost.faceCentre.z >= boardFront + MountainTrailPost.signClearance, "the face clears the board's front")
        #expect(MountainTrailPost.signClearance > 0)
        #expect(MountainTrailPost.faceSize.x < MountainTrailPost.boardSize.x && MountainTrailPost.faceSize.y < MountainTrailPost.boardSize.y, "the board frames the face")
        #expect(MountainTrailPost.signHeight + MountainTrailPost.boardSize.y / 2 > MountainTrailPost.shaftTop, "the sign reaches the top of the shaft, so the shaft ends behind it rather than above it")
    }

    /// The built post is the layout: shaft, board and face all hang off one mount turned toward
    /// the climber, and in that mount's frame the face's bounds lie wholly in front of the shaft's.
    @Test
    func theBuiltPostKeepsTheFaceInFrontOfTheShaft() throws {
        let post = MountainTrailPost.make(for: Self.marker, stone: UnlitMaterial())
        let mount = try #require(post.findEntity(named: MountainTrailPost.mountName))
        let shaft = try #require(post.findEntity(named: MountainTrailPost.shaftName))
        let board = try #require(post.findEntity(named: MountainTrailPost.boardName))
        let face = try #require(post.findEntity(named: MountainTrailPost.faceName))

        #expect(mount.position == MountainTrailPost.mountPosition)
        let forward = mount.orientation.act([0, 0, 1])
        #expect(forward.z > 0.9 && forward.x < -0.3, "the post faces the climber behind it and turns in toward the stairs: \(forward)")
        #expect(forward.y.isApproximatelyEqual(to: 0), "turned about the vertical only")
        for part in [shaft, board, face] {
            #expect(part.parent === mount, "\(part.name) hangs on the mount, so the whole post turns as one piece")
        }

        let shaftBounds = shaft.visualBounds(relativeTo: mount)
        let boardBounds = board.visualBounds(relativeTo: mount)
        let faceBounds = face.visualBounds(relativeTo: mount)
        #expect(boardBounds.min.z > shaftBounds.max.z, "board back \(boardBounds.min.z) must be past shaft front \(shaftBounds.max.z)")
        #expect(faceBounds.min.z > boardBounds.max.z - 1e-4, "face \(faceBounds.min.z) must be past board front \(boardBounds.max.z)")
        #expect(faceBounds.min.x > boardBounds.min.x && faceBounds.max.x < boardBounds.max.x)
        #expect(faceBounds.min.y > boardBounds.min.y && faceBounds.max.y < boardBounds.max.y)
        #expect(shaftBounds.min.y < -0.9, "the shaft stands in the ground on any slope")
    }

    /// From the climber's camera, over the whole approach to every post, the sight line to each
    /// corner and the centre of the number never passes through the shaft - far up the stairs
    /// and right beside it alike, so the count reads all the way in. A sign is only readable
    /// from in front of its face: seen edge-on or from behind, round a turn, no post could help
    /// and none may hurt, so those frames are not judged.
    @Test
    func theShaftNeverCrossesTheSightLineToTheNumber() throws {
        let world = try MountainWorld.bundled()
        var director = MountainSceneDirector(seed: MountainCourse.ascendMountainSeed, world: world)
        let half = MountainTrailPost.faceSize / 2
        let centre = MountainTrailPost.faceCentre
        let samples: [SIMD3<Float>] = [
            centre,
            centre + [-half.x, -half.y, 0], centre + [half.x, -half.y, 0],
            centre + [-half.x, half.y, 0], centre + [half.x, half.y, 0],
            centre + [-half.x, 0, 0], centre + [half.x, 0, 0],
            centre + [0, -half.y, 0], centre + [0, half.y, 0]
        ]
        let shaftLow = MountainTrailPost.shaftCentre - MountainTrailPost.shaftSize / 2
        let shaftHigh = MountainTrailPost.shaftCentre + MountainTrailPost.shaftSize / 2
        let mountToMarker = Transform(rotation: MountainTrailPost.mountOrientation, translation: MountainTrailPost.mountPosition).matrix

        var violations: [String] = []
        var farFrames = 0, nearFrames = 0, posts = Set<Int>()
        let stepsPerSecond = 3.4, frameSeconds = 1.0 / 30
        var time = 0.0, steps = 0.0
        _ = director.advance(logicalSteps: 0, time: 0, deltaTime: 0)
        while steps < 1_250 {
            steps += stepsPerSecond * frameSeconds
            time += frameSeconds
            let frame = director.advance(logicalSteps: Int(steps), time: time, deltaTime: frameSeconds)
            for placed in frame.markers where placed.marker.kind == .post {
                let markerToRender = Transform(rotation: simd_quatf(angle: placed.heading, axis: [0, 1, 0]), translation: placed.renderPosition).matrix
                let renderToMount = (markerToRender * mountToMarker).inverse
                let camera = (renderToMount * SIMD4(frame.cameraPosition, 1)).xyz
                guard camera.z > centre.z else { continue }
                posts.insert(placed.marker.step)
                let distance = simd_distance(frame.cameraPosition, placed.renderPosition)
                if distance > 30 { farFrames += 1 } else if distance < 5 { nearFrames += 1 }
                for sample in samples where Self.segment(from: camera, to: sample, crosses: shaftLow, shaftHigh) {
                    violations.append("step \(Int(steps)): post \(placed.marker.step) at \(String(format: "%.1f", distance)) m, sample \(sample)")
                }
            }
        }

        #expect(posts.count >= 10, "the climb faced posts \(posts.sorted())")
        #expect(farFrames > 0 && nearFrames > 0, "checked \(farFrames) far and \(nearFrames) near frames")
        #expect(violations.isEmpty, "the shaft crossed the number \(violations.count) times, first at \(violations.first ?? "-")")
    }

    /// A post stands at every hundred steps of the climber's whole life on the mountain, so its
    /// number grows to six digits and a comma. A number the border clips cannot be read, so the
    /// title shrinks to fit, and only when it must, so neighbouring posts match.
    @Test
    func aWideNumberShrinksToFitThePlaque() {
        let usable = MountainPlaque.imageSize.width - MountainPlaque.titleMargin * 2

        #expect(MountainPlaque.fittedTitleSize(for: "100", requested: 250) == 250)
        #expect(MountainPlaque.fittedTitleSize(for: "1,900", requested: 250) == 250)
        for title in ["16,900", "100,100", "1,000,100"] {
            let fitted = MountainPlaque.fittedTitleSize(for: title, requested: 250)
            let width = (title as NSString).size(withAttributes: [.font: MountainPlaque.titleFont(size: fitted)]).width
            #expect(fitted <= 250 && fitted > 60)
            #expect(width <= usable, "\(title) at \(fitted)pt is \(width)px wide, over \(usable)")
        }
        #expect(MountainPlaque.fittedTitleSize(for: "1,000,100", requested: 250) < MountainPlaque.fittedTitleSize(for: "100,100", requested: 250))
    }

    /// Whether the segment from `a` to `b` touches the box, ends included.
    private static func segment(from a: SIMD3<Float>, to b: SIMD3<Float>, crosses low: SIMD3<Float>, _ high: SIMD3<Float>) -> Bool {
        var tMin: Float = 0, tMax: Float = 1
        let direction = b - a
        for axis in 0..<3 {
            if abs(direction[axis]) < 1e-9 {
                if a[axis] < low[axis] || a[axis] > high[axis] { return false }
                continue
            }
            var t1 = (low[axis] - a[axis]) / direction[axis]
            var t2 = (high[axis] - a[axis]) / direction[axis]
            if t1 > t2 { swap(&t1, &t2) }
            tMin = max(tMin, t1)
            tMax = min(tMax, t2)
            if tMin > tMax { return false }
        }
        return true
    }
}

private extension Float {
    func isApproximatelyEqual(to other: Float, tolerance: Float = 1e-5) -> Bool {
        abs(self - other) <= tolerance
    }
}

private extension SIMD4<Float> {
    var xyz: SIMD3<Float> { [x, y, z] }
}
