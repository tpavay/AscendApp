import Testing
@testable import AscendApp

struct StableAvatarPaletteTests {
    /// Pinned values, so a change that reintroduces a per-launch seed - or any
    /// other change to which colour a climber gets - fails here rather than on
    /// the next launch.
    @Test
    func aClimberKeepsTheirColourAcrossLaunches() {
        #expect(StableAvatarPalette.index(for: "viktor", count: 4) == StableAvatarPalette.index(for: "viktor", count: 4))
        #expect(StableAvatarPalette.index(for: "", count: 4) == Int(0xcbf2_9ce4_8422_2325 as UInt64 % 4))
        #expect(StableAvatarPalette.index(for: "a", count: 1_000) == Int(0xaf63_dc4c_8601_ec8c as UInt64 % 1_000))
    }

    @Test
    func theIndexAlwaysFallsInsideThePalette() {
        for id in ["", "a", "kC8GSV7hCDZY9waZhIS9CimQ70y2", "current-user", "🧗‍♀️"] {
            #expect((0..<4).contains(StableAvatarPalette.index(for: id, count: 4)))
        }
        #expect(StableAvatarPalette.index(for: "anyone", count: 0) == 0)
    }

    @Test
    func differentClimbersSpreadAcrossThePalette() {
        let indices = Set((0..<40).map { StableAvatarPalette.index(for: "climber-\($0)", count: 4) })
        #expect(indices == [0, 1, 2, 3])
    }
}
