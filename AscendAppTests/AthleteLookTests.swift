import Foundation
import Testing
@testable import AscendApp

struct AthleteLookTests {
    /// Round 8's defaults: the body from the gender answer - body A for any answer that names
    /// none - a middle skin tone, that body's first hairstyle in dark brown, the Ascend kit,
    /// Regular and Some.
    @Test(arguments: ProfileGender.allCases.map(Optional.some) + [nil])
    func aNewAthleteStartsFromTheGenderAnswer(gender: ProfileGender?) {
        let look = AthleteLook.starting(for: gender)

        #expect(look.body == (gender == .woman ? .b : .a))
        #expect(look.hairStyle == look.body.firstHairStyle)
        #expect(look.skinTone == .tone3)
        #expect(look.hairColor == .darkBrown)
        #expect((look.top, look.bottom, look.shoes) == (.lime, .black, .white))
        #expect((look.size, look.muscle) == (.regular, .some))
    }

    @Test
    func switchingBodyMovesOnlyADefaultHairstyle() {
        let starting = AthleteLook.starting(for: .man)
        #expect(starting.switching(to: .b).hairStyle == .long, "the old body's first style follows the body")

        var chosen = starting
        chosen.hairStyle = .buzzed
        #expect(chosen.switching(to: .b).hairStyle == .buzzed, "a style the climber picked stays")
        #expect(chosen.switching(to: .b).body == .b)
    }

    @Test
    func theKitPaletteIsSixAndLimeIsTheAscendKit() {
        #expect(AthleteLook.KitColor.allCases.count == 6)
        #expect(AthleteLook.KitColor.lime.color == MountainColor(hex: "#86D30A"))
        #expect(AthleteLook.SkinTone.allCases.count == 6)
        #expect(AthleteLook.HairColor.allCases.count == 6)
    }

    /// The stored document is exactly the fields `firestore.rules` lists, spelled as the rules
    /// spell them, and reads back as the same look.
    @Test
    func theStoredLookIsThePresetsAndReadsBackWhole() throws {
        var look = AthleteLook.starting(for: .woman)
        look.hairColor = .darkBrown
        look.size = .big
        let payload = FirestoreAthleteLookRepository.payload(for: look)

        #expect(Set(payload.keys) == ["schemaVersion", "body", "skinTone", "hairStyle", "hairColor", "top", "bottom", "shoes", "size", "muscle", "updatedAt"])
        #expect(payload["hairColor"] as? String == "dark_brown")
        #expect(payload["body"] as? String == "b")
        #expect(FirestoreAthleteLookRepository.look(from: payload) == look)
    }

    @Test
    func aLookWithAnOptionThisBuildDoesNotOfferIsNotGuessedAt() {
        var payload = FirestoreAthleteLookRepository.payload(for: .starting(for: nil))
        payload["hairStyle"] = "mohawk"
        #expect(FirestoreAthleteLookRepository.look(from: payload) == nil)
        payload["hairStyle"] = nil
        #expect(FirestoreAthleteLookRepository.look(from: payload) == nil)
    }

    /// The athlete step follows the gender answer that picks its body, and the funnel counts it in
    /// the same place.
    @Test
    func theAthleteStepFollowsGender() {
        let stages = PostAuthOnboardingStage.allCases
        #expect(stages.firstIndex(of: .athlete) == stages.firstIndex(of: .gender).map { $0 + 1 })

        let ids = OnboardingAnalyticsContext.orderedStepIDs
        #expect(ids.firstIndex(of: "athlete") == ids.firstIndex(of: "gender").map { $0 + 1 })
        #expect(PostAuthOnboardingStage.athlete.analyticsInputType == "button")
    }

    /// Finished climbers' snapshots name every stage that existed when they finished, so a
    /// snapshot naming the athlete step decodes whole and nobody is sent back to onboarding.
    @Test
    func aSnapshotNamingTheAthleteStepDecodesEverywhere() throws {
        let snapshot = PostAuthOnboardingSnapshot(
            currentStage: .athlete,
            completedStages: Set(PostAuthOnboardingStage.allCases),
            isComplete: true
        )
        let decoded = try JSONDecoder().decode(PostAuthOnboardingSnapshot.self, from: JSONEncoder().encode(snapshot))

        #expect(decoded.isComplete)
        #expect(decoded.completedStages.contains(.athlete))
    }
}

@MainActor
struct AthleteLookStoreTests {
    private func store(_ repository: FakeAthleteLookRepository, gender: ProfileGender? = .woman) -> (AthleteLookStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: "athlete-look-store-\(UUID().uuidString)")!
        return (AthleteLookStore(repository: repository, genderSource: { _ in gender }, defaults: defaults), defaults)
    }

    @Test
    func aClimberWhoNeverSavedClimbsAsTheAthleteTheirGenderStartsThemWith() async {
        let (store, _) = store(FakeAthleteLookRepository(looks: [:]), gender: .woman)

        await store.load(userId: "me")

        #expect(store.saved == nil)
        #expect(store.current == .starting(for: .woman))
    }

    @Test
    func theGenderAnswerOnboardingJustGaveSurvivesTheFirstLoad() async {
        let (store, _) = store(FakeAthleteLookRepository(looks: [:], failing: ["me"]), gender: nil)
        store.start(with: .woman)

        await store.load(userId: "me")

        #expect(store.current == .starting(for: .woman))
    }

    @Test
    func anotherSignedInAccountStartsAfreshFromItsOwnAnswer() async {
        let (store, _) = store(FakeAthleteLookRepository(looks: [:]), gender: nil)
        store.start(with: .woman)
        await store.load(userId: "me")

        await store.load(userId: "someone-else")

        #expect(store.current == .starting(for: nil))
    }

    @Test
    func aSavedLookIsWornAndKeptOnTheDeviceForAnOfflineStart() async {
        var look = AthleteLook.starting(for: .man)
        look.top = .orange
        let repository = FakeAthleteLookRepository(looks: ["me": look])
        let (store, defaults) = store(repository)

        await store.load(userId: "me")
        #expect(store.current == look)

        let offline = AthleteLookStore(
            repository: FakeAthleteLookRepository(looks: [:], failing: ["me"]),
            genderSource: { _ in nil },
            defaults: defaults
        )
        await offline.load(userId: "me")
        #expect(offline.current == look, "the device's copy while the account cannot be read")
    }

    @Test
    func oneReadServesEverySurfaceAndAFailedReadIsTriedAgain() async {
        let repository = FakeAthleteLookRepository(looks: [:], failing: ["me"])
        let (store, _) = store(repository)

        await store.load(userId: "me")
        await store.load(userId: "me")
        #expect(repository.reads == ["me", "me"], "a failure is tried again")

        let answering = FakeAthleteLookRepository(looks: [:])
        let (settled, _) = self.store(answering)
        await settled.load(userId: "me")
        await settled.load(userId: "me")
        #expect(answering.reads == ["me"], "an answer is not asked for again")
    }

    @Test
    func anotherAccountNeverSeesTheLastOnesLook() async {
        var look = AthleteLook.starting(for: .man)
        look.hairColor = .red
        let (store, defaults) = store(FakeAthleteLookRepository(looks: ["me": look]))
        await store.load(userId: "me")

        await store.load(userId: "someone-else")
        #expect(store.saved == nil)

        store.clearAccountScopedState()
        #expect(defaults.data(forKey: AthleteLookStore.cacheKey) == nil, "sign-out leaves nothing of the account on the device")
    }

    @Test
    func saveKeepsOnlyWhatReachedTheAccount() async throws {
        let repository = FakeAthleteLookRepository(looks: [:])
        repository.failsSaving = true
        let (store, _) = store(repository)
        await store.load(userId: "me")
        var look = AthleteLook.starting(for: .man)
        look.size = .solid

        await #expect(throws: (any Error).self) { try await store.save(look, userId: "me") }
        #expect(store.saved == nil)

        repository.failsSaving = false
        try await store.save(look, userId: "me")
        #expect(store.current == look)
        #expect(repository.saves == [look])
    }

    @Test("The editor opened on a store nothing has loaded yet still shows the saved look")
    func theEditorOpenedBeforeAnyLoadShowsTheSavedLook() async {
        var look = AthleteLook.starting(for: .man)
        look.skinTone = .tone6
        let (saving, defaults) = store(FakeAthleteLookRepository(looks: [:]))
        try? await saving.save(look, userId: "me")

        // A relaunch: a fresh store over the same device copy, opened from the Just Climb chip
        // before Profile or a Mountain session has loaded it.
        let relaunched = AthleteLookStore(
            repository: FakeAthleteLookRepository(looks: ["me": look]),
            genderSource: { _ in .man },
            defaults: defaults
        )
        let model = AthleteEditorModel(look: relaunched.current)
        #expect(model.draft != look, "the precondition: the unread store offers the default")

        await model.loadSavedLook(userId: "me", from: relaunched)

        #expect(model.draft == look)
        #expect(!model.hasEdits)
        #expect(model.canSave)
    }

    @Test("A look the account answers with late never undoes a choice the climber tapped")
    func aLateAnswerKeepsTheClimbersEdits() async {
        var saved = AthleteLook.starting(for: .man)
        saved.hairColor = .red
        let (store, _) = store(FakeAthleteLookRepository(looks: ["me": saved]))
        let model = AthleteEditorModel(look: store.current)

        model.draft.top = .orange
        await model.loadSavedLook(userId: "me", from: store)

        #expect(model.draft.top == .orange)
        #expect(model.draft.hairColor != .red)
        #expect(model.hasEdits)
    }

    @Test
    func theEditorDressesOneGarmentAtATimeAndReportsAFailedSave() async {
        let repository = FakeAthleteLookRepository(looks: [:])
        let (store, _) = store(repository)
        let model = AthleteEditorModel(look: .starting(for: .man))

        model.garment = .shorts
        model.kitColor = .blue
        model.garment = .shoes
        model.kitColor = .black
        #expect((model.draft.top, model.draft.bottom, model.draft.shoes) == (.lime, .blue, .black))

        repository.failsSaving = true
        #expect(await model.save(userId: "me", to: store) == false)
        #expect(model.saveFailed)

        repository.failsSaving = false
        #expect(await model.save(userId: "me", to: store))
        #expect(!model.saveFailed)
        #expect(store.current == model.draft)
    }
}
