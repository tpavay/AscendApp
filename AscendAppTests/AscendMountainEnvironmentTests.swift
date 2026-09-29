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

    private static let profileJSON = """
    {
      "terrain": { "steepness": 1, "treeDensity": 0, "rockDensity": 0, "snowCover": 0 },
      "palette": { "grass": "#000000", "rock": "#000000", "snow": "#000000", "haze": "#000000", "foliage": "#000000" },
      "sky": { "zenith": "#000000", "horizon": "#000000", "sun": "#000000", "sunIntensity": 1 },
      "clouds": "none"
    }
    """

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

    /// Gates for big milestones, trail posts for small ones (captain, 2026-09-28): the posts repeat
    /// by rule, and a step that has its own gate keeps the gate.
    @Test
    func aRepeatingSeriesStandsPostsBetweenTheGates() throws {
        let world = MountainWorld(
            regions: try Self.map(),
            markers: [MountainMarker(id: "gate", step: 500, kind: .gate, design: "gate_stone", title: "500", subtitle: "STEPS")],
            markerSeries: [MountainMarkerSeries(id: "post", every: 100, subtitle: "STEPS")]
        )

        let near = world.markers(near: 380, behind: 12, ahead: 160)
        #expect(near.map(\.step) == [400, 500])
        #expect(near.map(\.kind) == [.post, .gate])
        #expect(near.first?.id == "post_400")
        #expect(near.first?.title == 400.formatted())
        #expect(world.markers(near: 0, behind: 12, ahead: 50).isEmpty, "no post at the start line")
    }

    @Test
    func markersDecodeKindAndDesignAndFallBackForUnknownOnes() throws {
        let data = Data("""
        {
          "regions": [{ "id": "region_01", "startStep": 0, "environment": \(Self.profileJSON) }],
          "markers": [
            { "id": "a", "step": 500, "title": "500" },
            { "id": "b", "step": 900, "kind": "post", "design": "post_stone", "title": "900" },
            { "id": "c", "step": 1000, "kind": "obelisk", "design": "not_in_this_build", "title": "1,000" }
          ],
          "markerSeries": [{ "id": "post", "every": 250, "subtitle": "STEPS" }]
        }
        """.utf8)

        let world = try MountainWorld(data: data)

        #expect(world.markers.map(\.kind) == [.gate, .post, .gate])
        #expect(world.markers.map(\.design) == [nil, "post_stone", "not_in_this_build"])
        #expect(world.markerSeries == [MountainMarkerSeries(id: "post", every: 250, kind: .post, subtitle: "STEPS")])
    }

    /// Climbers already pass 16,000 steps in one session (production, 2026-09-28), so the far end of
    /// the climb may not be one unchanging place.
    @Test
    func theBundledWorldKeepsChangingThroughTheLongestClimbs() throws {
        let regions = try MountainWorld.bundled().regions
        let ids = [10_000, 16_000, 30_000, 52_000, 100_000].map { regions.region(atSteps: Double($0)).id }

        #expect(Set(ids).count == ids.count, "\(ids)")
    }

    /// Half of all production climbs end before about 1,100 steps (2026-09-28), so the mountain has
    /// to visibly change inside the first 2,000 or most climbers never see it evolve.
    @Test
    func aTypicalClimbPassesThroughSeveralAreas() throws {
        let regions = try MountainWorld.bundled().regions
        let ids = Set(stride(from: 0.0, through: 2_000, by: 50).map { regions.region(atSteps: $0).id })

        #expect(ids.count >= 4, "\(ids.sorted())")
    }

    /// A gate at 500 and then every thousand steps, a trail post every hundred, and the heavier
    /// gate at the numbers the captain approved (2026-09-28); a post never takes a gate's stair.
    /// Where a heavier gate stands on a summit (round 16) it is the summit's gate - the same
    /// grand gate with its flag - which `AscendMountainJourneyTests` holds.
    @Test
    func theBundledWorldStandsAGateEveryThousandStepsAndAPostEveryHundred() throws {
        let world = try MountainWorld.bundled()
        let markers = world.markers(near: 5_000, behind: 1_000, ahead: 1_000)

        #expect(markers.filter { $0.kind == .gate }.map(\.step) == [4_000, 5_000, 6_000])
        #expect(markers.filter { $0.kind == .post }.count == 18, "21 hundreds from 4,000 to 6,000, three of them gates")
        #expect(Set(markers.map(\.step)).count == markers.count)
        #expect(world.markers(near: 490, behind: 0, ahead: 20).map(\.kind) == [.gate])
        for grand in [10_000, 20_000, 50_000, 100_000] {
            let gate = try #require(world.markers(near: Double(grand), behind: 0, ahead: 0).first)
            #expect(gate.kind == .gate && [MountainMarker.summitDesign, "gate_grand"].contains(gate.design), "\(grand)")
        }
    }

    /// "The user should be able to start climbing in the clouds at some point if they're climbing
    /// for long enough" (captain, 2026-09-28): somewhere up the bundled mountain the climb enters
    /// the cloud layer and comes out above it.
    @Test
    func aLongEnoughClimbEntersTheCloudsAndComesOutAboveThem() throws {
        let regions = try MountainWorld.bundled().regions.regions
        let inside = try #require(regions.firstIndex { $0.environment.clouds == .through })

        #expect(regions[(inside + 1)...].contains { $0.environment.clouds == .below })
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
            #expect(mesh.uvs.count == mesh.positions.count)
            #expect(mesh.faceMaterials.count == mesh.indices.count / 3)
            #expect(mesh.faceMaterials.allSatisfy { Int($0) < layout.materialCount })
            #expect(mesh.triangleCount >= patch.triangleCount)
        }
    }

    /// Both triangles of a cell of ground take one look, so the snow line follows the cells rather
    /// than running in long teeth down the slope, which the risen camera over a gate makes plain.
    @Test
    func eachCellOfGroundWearsOneLook() throws {
        let regions = try MountainWorld.bundled().regions
        var course = MountainCourse(seed: MountainCourse.ascendMountainSeed)

        for index in [0, 40, 400, 1_200, 2_400] {
            let patch = MountainTerrainPatch(placement: course.placement(at: index), regions: regions)
            for indices in patch.triangles.values {
                #expect(indices.count % 6 == 0, "piece \(index) has a cell split between looks")
                for cell in stride(from: 0, to: indices.count - 5, by: 6) {
                    let first = Set(indices[cell..<(cell + 3)].map { patch.positions[Int($0)] })
                    let second = Set(indices[(cell + 3)..<(cell + 6)].map { patch.positions[Int($0)] })
                    #expect(first.intersection(second).count == 2, "the two halves of one cell share its diagonal")
                }
            }
        }
    }
}

struct AscendMountainPropTests {
    /// The props are assets: a missing or truncated file would silently leave the mountain bare.
    @Test
    func theBundledPropsAreAPineAndABoulderOfSensibleSize() throws {
        let props = try MountainPropTemplate.load(from: .main)
        let pine = try #require(props["pine"])
        let boulder = try #require(props["boulder"])

        #expect((150...2_000).contains(pine.triangles.count))
        #expect((100...2_000).contains(boulder.triangles.count))
        #expect(Set(pine.triangles.map(\.part)) == [0, 1], "foliage and trunk")
        let heights = pine.triangles.flatMap { [$0.corners.0.y, $0.corners.1.y, $0.corners.2.y] }
        #expect((3...4.5).contains(heights.max() ?? 0), "a pine about 3.6 m tall")
        #expect(abs(Double(heights.max() ?? 0) - MountainTerrainPatch.pineHeight) < 0.1, "the height the canopy ceiling is kept with")
        let widths = boulder.triangles.flatMap { triangle in
            [triangle.corners.0, triangle.corners.1, triangle.corners.2].map { max(abs($0.x), abs($0.z)) }
        }
        #expect((0.4...0.7).contains(widths.max() ?? 0), "a boulder about a metre across")
    }
}

struct AscendMountainAthleteTests {
    private static func poser(body: AthleteLook.Body = .a) throws -> (MountainAthletePoser, MountainAthleteAsset) {
        let asset = try MountainAthleteAsset.bundled(MountainAthleteAsset.figureResource(body: body, size: .regular))
        return (try #require(MountainAthletePoser(asset: asset)), asset)
    }

    @Test
    func noStandInWearsTheClimbersLime() {
        let looks = (1...200).map { AthleteLook.standIn(for: "climber\($0)") }

        #expect(!looks.contains { $0.top == .lime })
        #expect(Set(looks.map(\.top)).count > 1)
        #expect(Set(looks.map(\.body)) == Set(AthleteLook.Body.allCases), "stand-ins come in both bodies")
        #expect(Set(looks.map(\.size)) == Set(AthleteLook.Size.allCases), "and every size")
        #expect(AthleteLook.standIn(for: "climber7") == AthleteLook.standIn(for: "climber7"), "the same climber always looks the same")
    }

    static let figures: [(AthleteLook.Body, AthleteLook.Size)] = AthleteLook.Body.allCases.flatMap { body in
        AthleteLook.Size.allCases.map { (body, $0) }
    }

    @Test(arguments: figures)
    func everyBodyAndSizeIsOneCleanSkinnedHuman(body: AthleteLook.Body, size: AthleteLook.Size) throws {
        let asset = try MountainAthleteAsset.bundled(MountainAthleteAsset.figureResource(body: body, size: size))

        #expect(asset.joints.count == 65)
        #expect((1.6...2.0).contains(asset.height), "life size: \(asset.height) m")
        #expect(asset.positions.count == asset.normals.count)
        #expect(asset.positions.count == asset.uvs.count)
        #expect(asset.indices.allSatisfy { Int($0) < asset.positions.count })
        #expect(asset.jointIndices.allSatisfy { indices in (0..<4).allSatisfy { indices[$0] >= 0 && Int(indices[$0]) < asset.joints.count } })
        #expect(asset.jointWeights.allSatisfy { abs(($0.x + $0.y + $0.z + $0.w) - 1) < 1e-3 })
        let brows = body == .a ? "hair" : "hair2"
        #expect(Set(asset.parts.map(\.slot)) == ["skin", brows, "eyes", "top", "bottom", "shoe", "shoeAccent"], "the whole kit is dressed, with no hair of its own")
        #expect(asset.parts.reduce(0) { $0 + $1.indexCount } == asset.indices.count)
        for textures in asset.textures.values {
            for file in [textures.baseColor, textures.normal, textures.roughness].compactMap({ $0 }) {
                #expect(Bundle.main.url(forResource: file, withExtension: nil) != nil, "\(file) ships with the app")
            }
        }
    }

    /// Every tone the editor offers has a skin baked to exactly its swatch, at every muscle level.
    @Test(arguments: AthleteLook.Body.allCases)
    func theSkinIsBakedForEveryToneTheEditorOffersAtEveryMuscleLevel(body: AthleteLook.Body) throws {
        let asset = try MountainAthleteAsset.bundled(MountainAthleteAsset.figureResource(body: body, size: .regular))

        #expect(Set(asset.skinTones.keys) == Set(AthleteLook.SkinTone.allCases.map(\.rawValue)))
        for tone in AthleteLook.SkinTone.allCases {
            #expect(asset.skinTones[tone.rawValue].flatMap(MountainColor.init(hex:)) == tone.color, "\(tone) is the swatch the build baked")
            for muscle in AthleteLook.Muscle.allCases {
                var look = AthleteLook.starting(for: nil)
                look.skinTone = tone
                look.muscle = muscle
                let textures = try #require(asset.textures[MountainAthleteRig.texturesKey(forSlot: "skin", look: look)])
                #expect(textures.baseColor != nil && textures.normal != nil && textures.roughness != nil)
            }
        }
    }

    @Test(arguments: AthleteLook.Body.allCases)
    func eachBodysHairPackHoldsEveryHairstyleOnThatBodysSkeleton(body: AthleteLook.Body) throws {
        let hair = try MountainAthleteAsset.bundled(MountainAthleteAsset.hairResource(body: body))

        #expect(Set(hair.parts.map(\.name)) == Set(AthleteLook.HairStyle.allCases.map { "hair.\($0.rawValue)" }))
        #expect(Set(hair.parts.map(\.slot)).isSubset(of: ["hair", "hair2"]))
        for size in AthleteLook.Size.allCases {
            let figure = try MountainAthleteAsset.bundled(MountainAthleteAsset.figureResource(body: body, size: size))
            #expect(hair.joints.map(\.name) == figure.joints.map(\.name))
            #expect(hair.joints.map(\.inverseBind) == figure.joints.map(\.inverseBind), "sizes change the body, never its bones")
        }
        for slot in ["hair", "hair2"] {
            let textures = try #require(hair.textures[slot])
            #expect((0.3...1).contains(textures.shade ?? 0), "hair is painted light, so any colour can tint it")
        }
    }

    /// The figure every look is drawn with: that body at that size, with that hairstyle.
    @Test(arguments: AthleteLook.Body.allCases, AthleteLook.HairStyle.allCases)
    func everyLookPutsTogetherIntoOneFigure(body: AthleteLook.Body, hairStyle: AthleteLook.HairStyle) async throws {
        let library = await MountainAthleteLibrary()
        var look = AthleteLook.starting(for: nil)
        look.body = body
        look.hairStyle = hairStyle
        let figure = try await library.figure(for: look)

        #expect(figure.pieces.filter { $0.part.name.hasPrefix("hair.") }.map(\.part.name) == ["hair.\(hairStyle.rawValue)"])
        #expect(figure.slots.contains("skin") && figure.slots.contains("top"))
        #expect(MountainAthletePoser(asset: figure.body) != nil)
    }

    /// Hair is painted grey and tinted: the tint is solved so the paint's average lands on the
    /// swatch, in linear light, for every colour the editor offers.
    @Test(arguments: AthleteLook.HairColor.allCases)
    func aHairTintLandsTheHairColourOnItsSwatch(color: AthleteLook.HairColor) throws {
        let hair = try MountainAthleteAsset.bundled(MountainAthleteAsset.hairResource(body: .a))
        let textures = try #require(hair.textures["hair"])
        let shade = try #require(textures.shade)
        var look = AthleteLook.starting(for: nil)
        look.hairColor = color

        let tint = MountainAthleteRig.tint(forSlot: "hair", look: look, textures: textures)
        let drawn = tint.linearScaled(by: shade)
        let swatch = color.color
        // A channel lighter than the paint can reach is held at white; the rest land exactly.
        #expect(abs(drawn.red - swatch.red) < 0.03)
        #expect(abs(drawn.green - swatch.green) < 0.01)
        #expect(abs(drawn.blue - swatch.blue) < 0.01)
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

        #expect(simd_distance(global[names.firstIndex(of: asset.roles.legs[0][2])!], left) < 1e-4)
        #expect(simd_distance(global[names.firstIndex(of: asset.roles.legs[1][2])!], right) < 1e-4)
        #expect(simd_distance(global[names.firstIndex(of: asset.roles.body)!], SIMD3(0, 0.76, 0)) < 1e-4)
    }

    @Test
    func legsKeepTheirLengthAndKneesBendForward() throws {
        let (poser, asset) = try Self.poser()
        let names = asset.joints.map(\.name)
        let rest = poser.globalPositions(of: asset.joints.map { .init(translation: SIMD3<Float>($0.restTranslation), rotation: $0.restRotation.float) })
        let posed = poser.globalPositions(of: poser.pose(Self.targets(left: SIMD3(0.12, 0.25, 0.15), right: SIMD3(-0.12, 0.03, -0.12))))

        for (side, leg) in zip(["left", "right"], asset.roles.legs) {
            let hip = names.firstIndex(of: leg[0])!, knee = names.firstIndex(of: leg[1])!
            #expect(abs(simd_distance(posed[hip], posed[knee]) - simd_distance(rest[hip], rest[knee])) < 1e-4)
            let foot = names.firstIndex(of: leg[2])!
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
        let hip = global[names.firstIndex(of: asset.roles.legs[0][0])!]
        let foot = global[names.firstIndex(of: asset.roles.legs[0][2])!]

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

    /// A gate across a bend stood askew with a pillar in the path, so a marker never stands inside
    /// a turn: it waits at the turn's exit, the first straight stair after the number is reached.
    @Test
    func aMarkerInsideATurnStandsAtTheTurnsExit() throws {
        var course = MountainCourse(seed: MountainCourse.ascendMountainSeed)
        let turn = try #require((0..<200).lazy.map { course.placement(at: $0) }.first { $0.kind == .leftTurn || $0.kind == .rightTurn })
        let flight = try #require((0..<200).lazy.map { course.placement(at: $0) }.first { $0.kind != .leftTurn && $0.kind != .rightTurn && $0.stepCount > 3 })

        #expect(course.markerStep(for: turn.firstStep) == turn.firstStep, "the turn's entry is still straight")
        for step in (turn.firstStep + 1)..<turn.endStep {
            #expect(course.markerStep(for: step) == turn.endStep)
        }
        #expect(course.markerStep(for: flight.firstStep + 2) == flight.firstStep + 2)
    }
}

struct AscendMountainCameraClearanceTests {
    /// The camera rides behind and above the climber, and at every turn its heading lags the
    /// stairs, so it swings out over the mountainside. No tree may stand where it passes: flying
    /// through a pine's crown fills the screen with needles (seen at step 240).
    @Test
    func theCameraNeverFliesThroughATree() throws {
        let world = try MountainWorld.bundled()
        var director = MountainSceneDirector(seed: MountainCourse.ascendMountainSeed, world: world)
        let pine = try #require(MountainPropTemplate.load(from: .main)["pine"])
        let corners = pine.triangles.flatMap { [$0.corners.0, $0.corners.1, $0.corners.2] }
        let pineHeight = Double(corners.map(\.y).max() ?? 0)
        let crownRadius = Double(corners.map { simd_length(SIMD2($0.x, $0.z)) }.max() ?? 0)

        var course = MountainCourse(seed: MountainCourse.ascendMountainSeed)
        var trees: [Int: [MountainDecorInstance]] = [:]
        var violations: [String] = []
        // A hard climber, whose camera lags the turns furthest.
        let stepsPerSecond = 3.4, frameSeconds = 1.0 / 30
        var time = 0.0, steps = 0.0
        _ = director.advance(logicalSteps: 0, time: 0, deltaTime: 0)
        while steps < 5_000 {
            steps += stepsPerSecond * frameSeconds
            time += frameSeconds
            let frame = director.advance(logicalSteps: Int(steps), time: time, deltaTime: frameSeconds)
            let camera = SIMD3<Double>(frame.cameraPosition)
            for slot in frame.slots where simd_distance(SIMD3<Double>(slot.renderPosition), camera) < 40 {
                let placed: [MountainDecorInstance]
                if let known = trees[slot.chunkIndex] {
                    placed = known
                } else {
                    let nearby = MountainSceneController.decorNeighbours(of: slot.placement, on: &course)
                    placed = MountainTerrainPatch(placement: slot.placement, regions: world.regions, nearby: nearby).trees
                    trees[slot.chunkIndex] = placed
                }
                let turn = simd_quatf(angle: slot.heading, axis: [0, 1, 0])
                for tree in placed {
                    let base = SIMD3<Double>(slot.renderPosition + turn.act(tree.position))
                    let top = base.y + Double(tree.scale) * pineHeight
                    let across = simd_distance(SIMD2(camera.x, camera.z), SIMD2(base.x, base.z))
                    if across < Double(tree.scale) * crownRadius + 0.3, camera.y > base.y, camera.y < top + 0.3 {
                        violations.append("step \(Int(steps)): piece \(slot.chunkIndex), tree \(String(format: "%.1f", Double(tree.scale) * pineHeight)) m tall, base y \(String(format: "%.2f", base.y)) camera y \(String(format: "%.2f", camera.y)) at \(String(format: "%.1f", across)) m, local \(tree.position)")
                    }
                }
            }
        }

        #expect(violations.isEmpty, "the camera passed through \(violations.count) trees, first at \(violations.first ?? "-")")
    }
}


extension AscendMountainCameraClearanceTests {
    /// The mountainside may rise beside the stairs, but never between the camera and the climber:
    /// at a turn the camera swings over the ground, and a hill there hid the climber (step 240).
    @Test
    func theGroundNeverHidesTheClimber() throws {
        let world = try MountainWorld.bundled()
        var director = MountainSceneDirector(seed: MountainCourse.ascendMountainSeed, world: world)
        var course = MountainCourse(seed: MountainCourse.ascendMountainSeed)
        struct Ground {
            let triangles: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)]
            let low: SIMD3<Float>
            let high: SIMD3<Float>
        }
        var grounds: [Int: Ground] = [:]
        var hidden: [String] = []
        let stepsPerSecond = 3.4, frameSeconds = 1.0 / 30
        var time = 0.0, steps = 0.0, frameCount = 0
        _ = director.advance(logicalSteps: 0, time: 0, deltaTime: 0)
        while steps < 5_000 {
            steps += stepsPerSecond * frameSeconds
            time += frameSeconds
            frameCount += 1
            let frame = director.advance(logicalSteps: Int(steps), time: time, deltaTime: frameSeconds)
            guard frameCount % 10 == 0 else { continue }
            let camera = frame.cameraPosition
            let chest = frame.athleteRenderHipCentre + SIMD3(0, 0.5, 0)
            for slot in frame.slots where simd_distance(slot.renderPosition, camera) < 45 {
                let ground: Ground
                if let known = grounds[slot.chunkIndex] {
                    ground = known
                } else {
                    let nearby = MountainSceneController.decorNeighbours(of: slot.placement, on: &course)
                    let patch = MountainTerrainPatch(placement: slot.placement, regions: world.regions, nearby: nearby)
                    let points = patch.positions
                    var triangles: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = []
                    var low = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
                    var high = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
                    for index in stride(from: 0, to: points.count, by: 3) {
                        triangles.append((points[index], points[index + 1], points[index + 2]))
                    }
                    for point in points {
                        low = simd_min(low, point)
                        high = simd_max(high, point)
                    }
                    ground = Ground(triangles: triangles, low: low, high: high)
                    grounds[slot.chunkIndex] = ground
                }
                // The sight line in the piece's own frame.
                let toLocal = simd_quatf(angle: -slot.heading, axis: [0, 1, 0])
                let from = toLocal.act(camera - slot.renderPosition), to = toLocal.act(chest - slot.renderPosition)
                let low = simd_min(from, to), high = simd_max(from, to)
                guard all(high .>= ground.low), all(low .<= ground.high) else { continue }
                for (a, b, c) in ground.triangles {
                    let tLow = simd_min(a, simd_min(b, c)), tHigh = simd_max(a, simd_max(b, c))
                    guard all(tHigh .>= low), all(tLow .<= high) else { continue }
                    if let t = Self.crossing(from: from, to: to, a, b, c), t > 0.02, t < 0.98 {
                        hidden.append("step \(Int(steps)): piece \(slot.chunkIndex) at \(String(format: "%.2f", t)) of the way to the climber")
                        break
                    }
                }
            }
        }

        #expect(hidden.isEmpty, "the ground hid the climber \(hidden.count) times, first at \(hidden.first ?? "-")")
    }

    /// Where the segment crosses the triangle, as a fraction of the way along it (Moller-Trumbore).
    private static func crossing(from: SIMD3<Float>, to: SIMD3<Float>, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) -> Float? {
        let direction = to - from
        let edge1 = b - a, edge2 = c - a
        let p = simd_cross(direction, edge2)
        let determinant = simd_dot(edge1, p)
        guard abs(determinant) > 1e-7 else { return nil }
        let inverse = 1 / determinant
        let s = from - a
        let u = simd_dot(s, p) * inverse
        guard u >= 0, u <= 1 else { return nil }
        let q = simd_cross(s, edge1)
        let v = simd_dot(direction, q) * inverse
        guard v >= 0, u + v <= 1 else { return nil }
        return simd_dot(edge2, q) * inverse
    }
}
