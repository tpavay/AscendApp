import Foundation
import simd
import Testing
@testable import AscendApp

struct AscendMountainRegionTests {
    private static func profile(steepness: Double = 1, grass: String = "#000000") -> MountainEnvironmentProfile {
        let color = MountainColor(hex: grass)!
        return MountainEnvironmentProfile(
            terrain: .init(steepness: steepness, treeDensity: 0, rockDensity: 0, snowCover: 0),
            palette: .init(grass: color, rock: color, snow: color, haze: color, foliage: color),
            sky: .init(zenith: color, horizon: color, sun: color, sunIntensity: 1),
            clouds: .none
        )
    }

    private static func map() throws -> MountainRegionMap {
        try MountainRegionMap(regions: [
            MountainRegion(id: "region_01", startStep: 0, endStep: 100, environment: profile(steepness: 1, grass: "#000000")),
            MountainRegion(id: "region_02", startStep: 100, endStep: 1_000, environment: profile(steepness: 2, grass: "#FFFFFF")),
            MountainRegion(id: "region_03", startStep: 1_000, endStep: nil, environment: profile(steepness: 3))
        ])
    }

    @Test
    func aStepCountSelectsItsRegion() throws {
        let map = try Self.map()

        #expect(map.region(atSteps: 0).id == "region_01")
        #expect(map.region(atSteps: 99.9).id == "region_01")
        #expect(map.region(atSteps: 100).id == "region_02")
        #expect(map.region(atSteps: 5_000_000).id == "region_03", "the last region never ends")
        #expect(map.region(atSteps: -10).id == "region_01")
        #expect(map.region(atSteps: .nan).id == "region_01")
    }

    @Test
    func regionValuesEaseIntoTheNextRatherThanStepping() throws {
        let map = try Self.map()
        var previous = map.blended({ $0.terrain.steepness }, atSteps: 600)

        for tenth in 6_000...10_100 {
            let value = map.blended({ $0.terrain.steepness }, atSteps: Double(tenth) / 10)
            #expect(value >= previous - 1e-12)
            #expect(value - previous < 0.01, "no jump anywhere across the boundary")
            previous = value
        }
        #expect(map.blended({ $0.terrain.steepness }, atSteps: 1_000) == 3)
        #expect(map.blendedColor({ $0.palette.grass }, atSteps: 700).red == 1, "inside a region, well before its transition")
    }

    @Test
    func aBrokenRegionTableIsRefused() {
        #expect(throws: MountainRegionMap.LoadError.empty) { try MountainRegionMap(regions: []) }
        #expect(throws: MountainRegionMap.LoadError.firstRegionDoesNotStartAtZero) {
            try MountainRegionMap(regions: [MountainRegion(id: "region_01", startStep: 5, endStep: nil, environment: Self.profile())])
        }
        #expect(throws: MountainRegionMap.LoadError.notContiguous("region_01")) {
            try MountainRegionMap(regions: [
                MountainRegion(id: "region_01", startStep: 0, endStep: 90, environment: Self.profile()),
                MountainRegion(id: "region_02", startStep: 100, endStep: nil, environment: Self.profile())
            ])
        }
        #expect(throws: MountainRegionMap.LoadError.notContiguous("region_01")) {
            try MountainRegionMap(regions: [MountainRegion(id: "region_01", startStep: 0, endStep: 50, environment: Self.profile())])
        }
    }

    /// Regions are undecided product content (captain, 2026-09-28): the bundled table may hold any
    /// provisional values, but only placeholder ids, and it must always describe one endless climb.
    @Test
    func theBundledWorldIsPlaceholderRegionsCoveringAnEndlessClimb() throws {
        let world = try MountainWorld.bundled()
        let ids = world.regions.regions.map(\.id)

        #expect(!ids.isEmpty)
        for (offset, id) in ids.enumerated() {
            #expect(id == String(format: "region_%02d", offset + 1), "placeholder ids only, in order: \(id)")
        }
        #expect(world.regions.regions.first?.startStep == 0)
        #expect(world.regions.regions.last?.endStep == nil)
        #expect(world.markers.map(\.step) == world.markers.map(\.step).sorted())
    }

    @Test
    func onlyMarkersNearTheClimberStandInTheWorld() throws {
        let world = MountainWorld(
            regions: try Self.map(),
            markers: [
                MountainMarker(id: "b", step: 900, title: "900", subtitle: nil),
                MountainMarker(id: "a", step: 300, title: "300", subtitle: nil)
            ]
        )

        #expect(world.markers.map(\.id) == ["a", "b"])
        #expect(world.markers(near: 100).isEmpty)
        #expect(world.markers(near: 200).map(\.id) == ["a"])
        #expect(world.markers(near: 305).map(\.id) == ["a"], "still standing just after it is passed")
        #expect(world.markers(near: 330).isEmpty)
    }
}

struct AscendMountainTerrainTests {
    private static func regions() throws -> MountainRegionMap {
        try MountainWorld.bundled().regions
    }

    private static func worldVertices(_ patch: MountainTerrainPatch, _ placement: MountainChunkPlacement) -> [SIMD3<Double>] {
        patch.positions.map { local in
            placement.entry.position + placement.entry.rotate(SIMD3<Double>(local))
        }
    }

    /// Every vertex of `a` lying on the plane where `b` begins has a twin in `b`: the two pieces'
    /// mountainsides share their edge exactly, so no crack can open at a join.
    private static func expectSeamless(_ a: MountainChunkPlacement, _ b: MountainChunkPlacement, regions: MountainRegionMap) {
        let planePoint = b.entry.position + b.entry.forward * (MountainStairGeometry.run / 2)
        let normal = b.entry.forward
        // Positions are stored as Float, so "on the plane" allows for single-precision rounding.
        func onPlane(_ p: SIMD3<Double>) -> Bool { abs(simd_dot(p - planePoint, normal)) < 1e-4 }

        let edgeA = worldVertices(MountainTerrainPatch(placement: a, regions: regions), a).filter(onPlane)
        let edgeB = worldVertices(MountainTerrainPatch(placement: b, regions: regions), b).filter(onPlane)

        #expect(!edgeA.isEmpty, "piece \(a.index) (\(a.kind)) reaches the join")
        for vertex in edgeA {
            // A turn builds ground only on its outside; on the inside the two flights' own slopes
            // meet each other, so an inner-side edge has no twin by design.
            let local = MountainPose(position: .zero, heading: -b.entry.heading).rotate(vertex - b.entry.position)
            if (b.kind == .leftTurn && local.x < 0) || (b.kind == .rightTurn && local.x > 0) { continue }
            let twin = edgeB.min { simd_distance($0, vertex) < simd_distance($1, vertex) }
            #expect(twin.map { simd_distance($0, vertex) < 1e-4 } == true, "\(a.kind) -> \(b.kind) edge vertex \(vertex) has no twin")
        }
    }

    @Test
    func mountainsidesMeetWithoutACrackAcrossEveryKindOfJoin() throws {
        let regions = try Self.regions()
        var course = MountainCourse(seed: MountainCourse.ascendMountainSeed)
        var joins = Set<String>()

        for index in 0..<80 {
            let a = course.placement(at: index), b = course.placement(at: index + 1)
            joins.insert("\(a.kind.isTurn ? "turn" : "straight")->\(b.kind.isTurn ? "turn" : "straight")")
            Self.expectSeamless(a, b, regions: regions)
        }
        #expect(joins.contains("straight->turn"))
        #expect(joins.contains("turn->straight"))
        #expect(joins.contains("straight->straight"))
    }

    @Test
    func theGroundFallsAwayFromTheStairsAndNeverFacesDown() throws {
        let regions = try Self.regions()
        var course = MountainCourse(seed: MountainCourse.ascendMountainSeed)

        for index in 0..<30 {
            let patch = MountainTerrainPatch(placement: course.placement(at: index), regions: regions)
            #expect(patch.triangleCount > 0)
            #expect(patch.normals.allSatisfy { $0.y >= -1e-6 })
        }
        #expect(MountainTerrainPatch.profile(distance: 0, steepness: 1) < 0, "the kerb stands proud of the ground")
        #expect(MountainTerrainPatch.profile(distance: 20, steepness: 1) < MountainTerrainPatch.profile(distance: 5, steepness: 1))
        #expect(MountainTerrainPatch.profile(distance: 10, steepness: 1.2) < MountainTerrainPatch.profile(distance: 10, steepness: 0.5))
    }

    @Test
    func aPieceIsRebuiltIdenticallyEveryTime() throws {
        let regions = try Self.regions()
        var course = MountainCourse(seed: MountainCourse.ascendMountainSeed)
        let placement = course.placement(at: 17)

        let first = MountainTerrainPatch(placement: placement, regions: regions)
        let second = MountainTerrainPatch(placement: placement, regions: regions)

        #expect(first.positions == second.positions)
        #expect(first.trees == second.trees)
        #expect(first.rocks == second.rocks)
    }

    @Test
    func trunksNeverStandOnTheStairs() throws {
        let regions = try Self.regions()
        var course = MountainCourse(seed: MountainCourse.ascendMountainSeed)
        let clearance = Float(MountainStairGeometry.width / 2 + MountainTerrainPatch.kerbWidth)

        for index in 0..<60 {
            let placement = course.placement(at: index)
            guard !placement.kind.isTurn else { continue }
            let patch = MountainTerrainPatch(placement: placement, regions: regions)
            for tree in patch.trees {
                #expect(abs(tree.position.x) > clearance + 1)
            }
        }
    }

    @Test
    func decorMeshReferencesOnlyTheSharedMaterialTable() throws {
        let regions = try Self.regions()
        var course = MountainCourse(seed: MountainCourse.ascendMountainSeed)
        let layout = MountainDecorMaterialLayout(regionCount: regions.regions.count)

        for index in [0, 40, 400] {
            let patch = MountainTerrainPatch(placement: course.placement(at: index), regions: regions)
            let mesh = MountainDecorMeshData(patch: patch, layout: layout)
            #expect(mesh.positions.count == mesh.indices.count)
            #expect(mesh.faceMaterials.count == mesh.indices.count / 3)
            #expect(mesh.faceMaterials.allSatisfy { Int($0) < layout.materialCount })
            #expect(mesh.triangleCount >= patch.triangleCount)
        }
    }
}

struct AscendMountainAthleteTests {
    private static func poser() throws -> (MountainAthletePoser, MountainAthleteAsset) {
        let asset = try MountainAthleteAsset.bundled()
        return (try #require(MountainAthletePoser(asset: asset)), asset)
    }

    @Test
    func theAthleteAssetIsOneCleanSkinnedHuman() throws {
        let asset = try MountainAthleteAsset.bundled()

        #expect(asset.joints.count == 62)
        #expect((1.6...2.0).contains(asset.height), "life size: \(asset.height) m")
        #expect(asset.positions.count == asset.normals.count)
        #expect(asset.indices.allSatisfy { Int($0) < asset.positions.count })
        #expect(asset.jointIndices.allSatisfy { indices in (0..<4).allSatisfy { indices[$0] >= 0 && Int(indices[$0]) < asset.joints.count } })
        #expect(asset.jointWeights.allSatisfy { abs(($0.x + $0.y + $0.z + $0.w) - 1) < 1e-3 })
        let known: Set<String> = ["skin", "skinShade", "hair", "eyes", "top", "bottom", "shoe", "shoeAccent"]
        #expect(Set(asset.parts.map(\.slot)).isSubset(of: known))
        #expect(asset.parts.reduce(0) { $0 + $1.indexCount } == asset.indices.count)
    }

    private static func targets(left: SIMD3<Double>, right: SIMD3<Double>, pelvisHeight: Double = 0.76) -> MountainAthletePoseTargets {
        MountainAthletePoseTargets(
            pelvis: SIMD3(0, pelvisHeight, 0),
            leftFoot: left,
            rightFoot: right,
            torsoLean: 0.2,
            leftArmSwing: 0.3,
            elbowBend: 0.6,
            twist: 0.05
        )
    }

    @Test
    func feetLandExactlyWhereTheCourseSays() throws {
        let (poser, asset) = try Self.poser()
        let names = asset.joints.map(\.name)
        let left = SIMD3<Double>(0.12, 0.2, 0.12), right = SIMD3<Double>(-0.12, 0.03, -0.15)

        let local = poser.pose(Self.targets(left: left, right: right))
        let global = poser.globalPositions(of: local)

        #expect(simd_distance(global[names.firstIndex(of: "Foot.L")!], left) < 1e-4)
        #expect(simd_distance(global[names.firstIndex(of: "Foot.R")!], right) < 1e-4)
        #expect(simd_distance(global[names.firstIndex(of: "Body")!], SIMD3(0, 0.76, 0)) < 1e-4)
    }

    @Test
    func legsKeepTheirLengthAndKneesBendForward() throws {
        let (poser, asset) = try Self.poser()
        let names = asset.joints.map(\.name)
        let rest = poser.globalPositions(of: asset.joints.map { .init(translation: SIMD3<Float>($0.restTranslation), rotation: $0.restRotation.float) })
        let posed = poser.globalPositions(of: poser.pose(Self.targets(left: SIMD3(0.12, 0.25, 0.15), right: SIMD3(-0.12, 0.03, -0.12))))

        for side in ["L", "R"] {
            let hip = names.firstIndex(of: "UpperLeg.\(side)")!, knee = names.firstIndex(of: "LowerLeg.\(side)")!
            #expect(abs(simd_distance(posed[hip], posed[knee]) - simd_distance(rest[hip], rest[knee])) < 1e-4)
            let foot = names.firstIndex(of: "Foot.\(side)")!
            let midpoint = (posed[hip] + posed[foot]) / 2
            #expect(posed[knee].z > midpoint.z, "the \(side) knee points up the stairs")
        }
    }

    @Test
    func aFootOutOfReachLiftsTheHeelInsteadOfTearingFromTheLeg() throws {
        let (poser, asset) = try Self.poser()
        let names = asset.joints.map(\.name)
        let farBelow = SIMD3<Double>(0.12, -0.6, 0)

        let global = poser.globalPositions(of: poser.pose(Self.targets(left: farBelow, right: SIMD3(-0.12, 0.03, 0))))
        let hip = global[names.firstIndex(of: "UpperLeg.L")!]
        let foot = global[names.firstIndex(of: "Foot.L")!]

        #expect(foot.y > farBelow.y)
        #expect(simd_distance(hip, foot) < 1.2)
    }

    @Test
    func theSwingingFootClearsTheNoseOfTheStairItPasses() {
        var course = MountainCourse(seed: MountainCourse.ascendMountainSeed)
        let rise = MountainStairGeometry.rise, run = MountainStairGeometry.run

        for tenth in 0...100 {
            let steps = 6 + Double(tenth) / 100
            let athlete = MountainAthleteKinematics(visualSteps: steps, intensity: 0.3, movement: 1, time: 0) { course.progress(atSteps: $0).pose }
            // Stair 6 is the stance tread; the right foot swings from 5 to 7 over its nose.
            let swing = athlete.rightFoot
            let noseOfSeven = -7 * run + run / 2
            if swing.z < -6 * run + run / 2 && swing.z > noseOfSeven {
                #expect(swing.y >= 6 * rise - 1e-9, "over tread 6 at \(steps)")
            }
            if swing.z <= noseOfSeven + 0.02 {
                #expect(swing.y >= 7 * rise - 0.02, "past the nose of 7 at \(steps)")
            }
        }
    }
}

struct AscendMountainMarkerFrameTests {
    @Test
    func aMarkerStandsOnItsStairInRenderSpace() throws {
        let world = MountainWorld(
            regions: try MountainWorld.bundled().regions,
            markers: [MountainMarker(id: "m", step: 40, title: "40", subtitle: "STEPS")]
        )
        var director = MountainSceneDirector(seed: MountainCourse.ascendMountainSeed, world: world)
        var course = MountainCourse(seed: MountainCourse.ascendMountainSeed)

        let frame = director.advance(logicalSteps: 30, time: 0, deltaTime: 0)
        let marker = try #require(frame.markers.first)
        let expected = course.progress(atSteps: 40).pose.position - frame.renderOrigin

        #expect(marker.marker.id == "m")
        #expect(simd_distance(SIMD3<Double>(marker.renderPosition), expected) < 1e-3)
        #expect(director.advance(logicalSteps: 300, time: 1, deltaTime: 0.016).markers.isEmpty)
    }
}
