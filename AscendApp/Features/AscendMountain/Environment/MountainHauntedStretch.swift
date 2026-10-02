import Foundation

/// October's haunted stretch: the first steps of every climb turn to night - a purple sky, dark
/// ground - with lit jack-o'-lanterns lining the stairs, ghosts drifting beside them, and gates
/// hung with webs and spiders under purple and orange light. It starts wherever the climber's
/// journey resumes, so a climber far up the mountain sees it as surely as a new one.
///
/// Which events dress the mountain this way, and for how many steps, is the unlock catalogue's
/// (`UnlockEvent.theme`); this is only how it looks.
enum MountainHauntedStretch {
    /// The marker design of a lantern at the stair's edge, and of a gate inside the stretch.
    static let lanternDesign = "haunted_lantern"
    static let gateDesign = "gate_haunted"
    /// A lantern stands every this many steps, alternating sides.
    static let lanternEvery = 10

    static let palette = MountainEnvironmentProfile.Palette(
        grass: MountainColor(hex: "#1C2216")!,
        rock: MountainColor(hex: "#3A3442")!,
        snow: MountainColor(hex: "#8A84A0")!,
        haze: MountainColor(hex: "#4A2D66")!,
        foliage: MountainColor(hex: "#0D110C")!
    )

    static let sky = MountainEnvironmentProfile.Sky(
        zenith: MountainColor(hex: "#07040F")!,
        horizon: MountainColor(hex: "#5A2F78")!,
        sun: MountainColor(hex: "#C2B4FF")!,
        sunIntensity: 1.5
    )

    /// The world with the steps `start..<start + length` dressed for Halloween. Regions are cut
    /// at both ends of the stretch, so the mountain eases into the night and back out again over
    /// the usual region transition.
    static func dress(_ world: MountainWorld, from start: Int, length: Int) -> MountainWorld {
        guard length > 0 else { return world }
        let stretch = max(start, 0)..<(max(start, 0) + length)
        var regions: [MountainRegion] = []
        for region in world.regions.regions {
            let end = region.endStep ?? Int.max
            // Up to three slices: before the stretch, inside it, after it.
            let cuts = [region.startStep, max(region.startStep, min(stretch.lowerBound, end)), max(region.startStep, min(stretch.upperBound, end)), end]
            for (index, (from, to)) in zip(cuts, cuts.dropFirst()).enumerated() where from < to {
                let haunted = index == 1
                regions.append(MountainRegion(
                    id: haunted ? "\(region.id)_haunted" : (index == 0 ? region.id : "\(region.id)_after"),
                    startStep: from,
                    endStep: to == Int.max ? nil : to,
                    environment: haunted ? haunt(region.environment) : region.environment
                ))
            }
        }
        guard let map = try? MountainRegionMap(regions: regions) else { return world }
        let lanterns = MountainMarkerSeries(id: "haunted_lantern", every: lanternEvery, kind: .post, design: lanternDesign, subtitle: nil, range: stretch)
        return MountainWorld(regions: map, markers: world.markers, markerSeries: world.markerSeries + [lanterns], haunted: stretch)
    }

    /// The region's own ground and slopes, under a Halloween night.
    private static func haunt(_ environment: MountainEnvironmentProfile) -> MountainEnvironmentProfile {
        MountainEnvironmentProfile(terrain: environment.terrain, palette: palette, sky: sky, clouds: .none)
    }
}
