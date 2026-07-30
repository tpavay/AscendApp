import Testing
@testable import AscendApp

struct DisplayNamePolicyTests {
    @Test
    func acceptsAndTrimsOrdinaryDisplayName() throws {
        #expect(try DisplayNamePolicy.validated("  Summit Chaser  ") == "Summit Chaser")
    }

    @Test(arguments: [
        "fuck",
        "f.u.c.k",
        "fück",
        "f4gg0t",
        "m.o.t.h.e.r.f.u.c.k.e.r",
        "a$s-h0le",
        "s.h.i.t",
        "r@pist",
        "white power",
        "kill-yourself",
        "friendlyniggername",
        "fuсk",
        "fυck",
        "fucκ",
        "fսck",
        "ｆｕｃｋ",
        "ｎｉｇｇｅｒ",
        "fuuuck",
        "Maaaya",
        "asshole",
        " Anonymous Climber "
    ])
    func rejectsObjectionableDisplayNames(_ displayName: String) {
        #expect(throws: DisplayNamePolicyError.self) {
            try DisplayNamePolicy.validated(displayName)
        }
    }

    @Test(arguments: [
        "Nazim",
        "Scunthorpe",
        "Classic",
        "Passionate Climber",
        "Марія",
        "Søren"
    ])
    func acceptsNamesThatContainOnlyIncidentalLetterSequences(
        _ displayName: String
    ) throws {
        #expect(try DisplayNamePolicy.validated(displayName) == displayName)
    }

    @Test
    func rejectsEmptyAndOverlongDisplayNames() {
        #expect(throws: DisplayNamePolicyError.self) {
            try DisplayNamePolicy.validated("  ")
        }
        #expect(throws: DisplayNamePolicyError.self) {
            try DisplayNamePolicy.validated(
                String(repeating: "A", count: DisplayNamePolicy.maximumLength + 1)
            )
        }
    }

    @Test
    @MainActor
    func authenticationRejectsDisplayNameBeforeProfileMutation() async {
        var mutationCount = 0

        await #expect(throws: DisplayNamePolicyError.self) {
            try await AuthenticationService.commitValidatedDisplayName(
                "ｎｉｇｇｅｒ"
            ) { _ in
                mutationCount += 1
            }
        }

        #expect(mutationCount == 0)
    }
}
