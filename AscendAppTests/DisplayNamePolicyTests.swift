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
        "fųck",
        "f𝕦ck",
        "fⓤck",
        "f⒰ck",
        "f🅤ck",
        "fᵘck",
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

    /// A wrongly rejected legitimate name costs more than a marginal one
    /// slipping through, and leetspeak folding ran before the repeated-character
    /// check, so `Climber2000` normalized to `climber2ooo` and tripped it.
    @Test
    func keepsOrdinaryNamesContainingDigits() throws {
        for name in [
            "Climber2000",
            "Runner000",
            "Team111",
            "Level333",
            "Route555",
            "Step777"
        ] {
            #expect(DisplayNamePolicy.isAllowed(name), "rejected \(name)")
            #expect(try DisplayNamePolicy.validated(name) == name)
        }
    }

    /// U+02BB okina and U+02BC modifier apostrophe are ordinary letters in
    /// Hawaiian and many other orthographies.
    @Test
    func keepsNamesUsingTheOkina() throws {
        #expect(try DisplayNamePolicy.validated("Ka\u{02BB}iulani") == "Ka\u{02BB}iulani")
        #expect(DisplayNamePolicy.isAllowed("O\u{02BC}ahu Climber"))
    }

    /// The okina allowlist must not open a hole in the account-deletion
    /// sentinel: the Cloud Functions validator strips U+02BB as a diacritic and
    /// the rules pattern absorbs it, so the client has to reject it too or the
    /// server denies a write the client just accepted.
    @Test
    func anonymousClimberSentinelSurvivesTheOkinaAllowlist() {
        #expect(!DisplayNamePolicy.isAllowed("Anonymous\u{02BB} Climber"))
        #expect(!DisplayNamePolicy.isAllowed("Anonymous\u{02BC}Climber"))
        #expect(!DisplayNamePolicy.isAllowed("Anonymous Climber"))
        #expect(DisplayNamePolicy.isAllowed("Ka\u{02BB}iulani"))
    }

    @Test
    func stillRejectsRepeatedLettersAndModifierLetterObfuscation() {
        #expect(!DisplayNamePolicy.isAllowed("fuuuck"))
        #expect(!DisplayNamePolicy.isAllowed("Cliiimber"))
        #expect(!DisplayNamePolicy.isAllowed("Climber\u{02B0}"))
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
