import Foundation
import Testing
@testable import AscendApp

/// The decisions behind screens 07b, 08, 09 and 11, with no view: usual-climb answers, the climber
/// card's age, ranges and steps, the city count's key and copy, and which version of the monthly
/// event shows on which day.
@MainActor
struct OnboardingV3SetupTests {
    private let utc = TimeZone(secondsFromGMT: 0) ?? .gmt

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? .distantPast
    }

    // MARK: - 07b

    @Test
    func theUsualClimbRowsStoreTheNumbersTheDesignPromises() {
        #expect(UsualClimbChoice.newToThis.steps == 1_000)
        #expect(UsualClimbChoice.newToThis.minutes == 12)
        #expect(UsualClimbChoice.underFifteen.detail == "~1,000 steps")
        #expect(UsualClimbChoice.fifteenToThirty.detail == "~1,800 steps")
        #expect(UsualClimbChoice.thirtyToFortyFive.detail == "~3,000 steps")
        #expect(UsualClimbChoice.fortyFiveOrMore.detail == "~4,500 steps")
    }

    @Test
    func everyRowReadsBackAsItselfAndNoRowStealsAnother() {
        for choice in UsualClimbChoice.allCases {
            #expect(UsualClimbChoice.stored(steps: choice.steps, minutes: choice.minutes) == choice)
        }
        #expect(Set(UsualClimbChoice.allCases.map { "\($0.steps)/\($0.minutes)" }).count == UsualClimbChoice.allCases.count)
        #expect(UsualClimbChoice.stored(steps: 3_260, minutes: 41) == nil, "a Health history's usual climb lights no row")
        #expect(UsualClimbChoice.stored(steps: nil, minutes: nil) == nil)
    }

    // MARK: - 08

    private func draft(system: MeasurementSystem = .imperial) -> ClimberCardDraft {
        ClimberCardDraft(answers: PreAuthOnboardingAnswers(), system: system)
    }

    @Test
    func aBirthdayGivesTheAgeOnTheDayItIsReached() {
        var card = draft()
        card.birthday = PreAuthOnboardingBirthday(year: 1998, month: 11, day: 5)

        #expect(card.age(on: date(2026, 11, 4), calendar: calendar) == 27)
        #expect(card.age(on: date(2026, 11, 5), calendar: calendar) == 28)
    }

    @Test
    func agesOutsideThirteenToNinetyNineGiveNoAge() {
        var card = draft()
        card.birthday = PreAuthOnboardingBirthday(year: 2016, month: 1, day: 1)
        #expect(card.age(on: date(2026, 11, 4), calendar: calendar) == nil, "ten is under the floor")

        card.birthday = PreAuthOnboardingBirthday(year: 1900, month: 1, day: 1)
        #expect(card.age(on: date(2026, 11, 4), calendar: calendar) == nil)

        card.birthday = PreAuthOnboardingBirthday(year: 2013, month: 11, day: 4)
        #expect(card.age(on: date(2026, 11, 4), calendar: calendar) == 13, "thirteen today is the youngest")
    }

    @Test
    func theWheelOffersOnlyBirthdaysThatGiveAnAcceptedAge() {
        let today = date(2026, 11, 4)
        let range = ClimberCardDraft.birthdayRange(on: today, calendar: calendar)

        var youngest = draft()
        youngest.setBirthday(from: range.upperBound, calendar: calendar)
        #expect(youngest.age(on: today, calendar: calendar) == 13)

        var oldest = draft()
        oldest.setBirthday(from: range.lowerBound, calendar: calendar)
        #expect(oldest.age(on: today, calendar: calendar) == 99)
    }

    @Test
    func heightStepsAnInchAndStartsFromSixtySevenWhenNothingIsSet() {
        var card = draft()
        card.stepHeight(1)
        #expect(card.heightText == "5'7\"")
        card.stepHeight(1)
        #expect(card.heightText == "5'8\"")
        card.stepHeight(-1); card.stepHeight(-1)
        #expect(card.heightText == "5'6\"")
    }

    @Test
    func heightAndWeightStopAtTheirRanges() {
        var card = draft()
        for _ in 0..<80 { card.stepHeight(1) }
        #expect(card.heightText == "7'6\"", "90 inches is the ceiling")
        for _ in 0..<80 { card.stepHeight(-1) }
        #expect(card.heightText == "4'0\"", "48 inches is the floor")

        for _ in 0..<400 { card.stepWeight(1) }
        #expect(card.weightText == "400 lb")
        for _ in 0..<400 { card.stepWeight(-1) }
        #expect(card.weightText == "80 lb")
    }

    @Test
    func unitsFollowThePhonesMeasurementSystem() {
        var metric = draft(system: .metric)
        metric.stepHeight(1)
        metric.stepWeight(1)
        #expect(metric.heightText == "170 cm")
        #expect(metric.weightText == "72 kg")
        #expect(metric.heightCm == 170)
        #expect(metric.weightKg == 72)

        var imperial = draft(system: .imperial)
        imperial.stepWeight(1)
        #expect(imperial.weightText == "160 lb")
        #expect(abs((imperial.weightKg ?? 0) - 72.57) < 0.05, "stored in kilograms")
    }

    @Test
    func aStoredValueReadsTheSameInEitherSystem() {
        var answers = PreAuthOnboardingAnswers()
        answers.heightCm = 177.8
        answers.weightKg = 79.37866
        #expect(ClimberCardDraft(answers: answers, system: .imperial).heightText == "5'10\"")
        #expect(ClimberCardDraft(answers: answers, system: .imperial).weightText == "175 lb")
        #expect(ClimberCardDraft(answers: answers, system: .metric).heightText == "178 cm")
    }

    @Test
    func theGenderTileNamesEachChoiceAndHidesNothingButPrivate() {
        var card = draft()
        #expect(card.genderTileText == nil, "nothing preselected")
        card.gender = .man
        #expect(card.genderTileText == "Male")
        card.gender = .woman
        #expect(card.genderTileText == "Female")
        card.gender = .nonBinary
        #expect(card.genderTileText == "Other")
        card.gender = .preferNotToSay
        #expect(card.genderTileText == "Private")
        #expect(ClimberCardDraft.genderChoices.map(\.title) == ["Male", "Female", "Other", "Prefer not to say"])
    }

    @Test
    func continuingWritesTheCardAndAnEmptyCardWritesNothing() {
        var answers = PreAuthOnboardingAnswers()
        draft().apply(to: &answers)
        #expect(answers == PreAuthOnboardingAnswers())

        var card = draft()
        card.gender = .woman
        card.birthday = PreAuthOnboardingBirthday(year: 1990, month: 6, day: 15)
        card.stepHeight(1)
        card.apply(to: &answers)
        #expect(answers.gender == .woman)
        #expect(answers.birthday == PreAuthOnboardingBirthday(year: 1990, month: 6, day: 15))
        #expect(answers.heightCm != nil)
        #expect(answers.weightKg == nil)
    }

    @Test
    func aTapOnTheChosenChipClearsItAgain() {
        var answers = PreAuthOnboardingAnswers()
        answers.gender = .man
        var card = ClimberCardDraft(answers: answers, system: .imperial)
        card.gender = nil
        card.apply(to: &answers)
        #expect(answers.gender == nil)
    }

    // MARK: - 09

    private struct KeyVector: Decodable {
        struct Case: Decodable {
            let city: String
            let region: String?
            let countryCode: String
            let key: String
        }
        let cases: [Case]
    }

    @Test
    func theCityKeyMatchesTheServersOnEverySharedVectorCase() throws {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "SharedTestVectors/city-count-key-vector.json")
        let vector = try JSONDecoder().decode(KeyVector.self, from: Data(contentsOf: url))

        for entry in vector.cases {
            #expect(
                CityClimberCountKey.key(city: entry.city, region: entry.region, countryCode: entry.countryCode) == entry.key,
                "\(entry.city), \(entry.region ?? "-"), \(entry.countryCode)"
            )
        }
        #expect(CityClimberCountKey.key(city: "...", region: nil, countryCode: "US") == nil)
        #expect(CityClimberCountKey.key(city: "Chicago", region: nil, countryCode: "USA") == nil)
    }

    private let chicago = PostAuthLocationSelection(city: "Chicago", region: "IL", countryCode: "US", countryName: "United States")

    @Test
    func aZeroCountSaysNothingAboutWhoHasClimbedAndANonZeroOneKeepsTheDesignsBadge() {
        let empty = OnboardingCityClaimCopy(selection: chicago, count: .climbers(0))
        #expect(empty.badgePlace == "CHICAGO")
        #expect(empty.badgePill == "OPEN")
        #expect(empty.body == "Be among the first climbers in Chicago. Your first climb puts you on the Chicago board.")
        #expect(!empty.body.contains("Nobody"), "a zero can be a spelling another phone stored differently")
        #expect(!empty.body.contains("has climbed"))

        let some = OnboardingCityClaimCopy(selection: chicago, count: .climbers(12))
        #expect(some.body == "12 climbers in Chicago so far.")
        #expect(some.badgePill == "OPEN", "no outward copy beyond the design")
        #expect(OnboardingCityClaimCopy(selection: chicago, count: .climbers(1)).body == "1 climber in Chicago so far.")
        #expect(!some.body.contains("rank"), "no estimated rank")
    }

    @Test
    func aCountThatCouldNotBeReadNeverBecomesAGuessedZero() {
        for count in [CityClimberCount.unknown, nil] {
            let copy = OnboardingCityClaimCopy(selection: chicago, count: count)
            #expect(copy.body == OnboardingCityClaimCopy.introduction)
            #expect(!copy.body.contains("Nobody"))
            #expect(copy.badgePlace == "YOUR CITY")
        }
        let before = OnboardingCityClaimCopy(selection: nil, count: nil)
        #expect(before.badgePlace == "YOUR CITY")
        #expect(!before.hasCity)
    }

    // MARK: - Skip clears what an earlier pass stored

    private func coordinator(_ configure: (inout PreAuthOnboardingAnswers) -> Void) -> OnboardingV3Coordinator {
        let suite = "onboarding-v3-skip-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let coordinator = OnboardingV3Coordinator(store: PreAuthOnboardingStore(userDefaults: defaults), startingAt: .climberCard)
        coordinator.update(configure)
        return coordinator
    }

    @Test
    func goingBackToTheClimberCardAndSkippingClearsItsEarlierAnswers() {
        let coordinator = coordinator {
            $0.gender = .woman
            $0.birthday = PreAuthOnboardingBirthday(year: 1990, month: 6, day: 15)
            $0.heightCm = 170
            $0.weightKg = 70
            $0.usualClimbSteps = 1_800
        }

        OnboardingClimberCardScreen.skip(coordinator)

        #expect(coordinator.answers.gender == nil)
        #expect(coordinator.answers.birthday == nil)
        #expect(coordinator.answers.heightCm == nil)
        #expect(coordinator.answers.weightKg == nil)
        #expect(coordinator.answers.usualClimbSteps == 1_800, "other screens' answers stay")
        #expect(coordinator.step == .claimCity)
    }

    @Test
    func goingBackToTheCityAndSkippingClearsTheCityClaimedBefore() {
        let coordinator = coordinator {
            $0.city = PreAuthOnboardingCity(city: "Chicago", region: "IL", countryCode: "US", countryName: "United States")
            $0.gender = .man
        }

        OnboardingClaimCityScreen.skip(coordinator)

        #expect(coordinator.answers.city == nil)
        #expect(coordinator.answers.gender == .man, "other screens' answers stay")
        #expect(coordinator.step == .claimCity || coordinator.step == .weeklyTarget)
    }

    @Test
    func skippingTheTargetStillClearsAnEarlierOne() {
        let coordinator = coordinator { $0.weeklyTargetDays = 4 }

        OnboardingWeeklyTargetScreen.skip(coordinator)

        #expect(coordinator.answers.weeklyTargetDays == nil)
    }

    private struct FakeReader: CityClimberCountReading {
        let result: CityClimberCount
        func count(for selection: PostAuthLocationSelection) async -> CityClimberCount { result }
    }

    @Test
    func pickingACityShowsItAtOnceThenFillsInTheCount() async {
        let model = OnboardingCityClaimModel(reader: FakeReader(result: .climbers(7)))
        #expect(model.phase == .prompt)

        await model.claim(chicago)

        #expect(model.phase == .located(chicago, .climbers(7)))
        #expect(model.selection == chicago)
    }

    @Test
    func aCityRestoredFromTheAnswersFetchesItsCountOnReturn() async {
        let stored = PreAuthOnboardingCity(chicago)
        let model = OnboardingCityClaimModel(reader: FakeReader(result: .climbers(0)), initialCity: stored)
        #expect(model.phase == .located(chicago, nil))

        await model.refreshCount()

        #expect(model.phase == .located(chicago, .climbers(0)))
    }

    // MARK: - 11


    private func event(_ id: String, _ title: String, _ month: String, from start: String, to end: String) -> UnlockEvent? {
        let json = #"{"id":"\#(id)","title":"\#(title)","monthName":"\#(month)","startsOn":"\#(start)","endsBefore":"\#(end)"}"#
        return try? JSONDecoder().decode(UnlockEvent.self, from: Data(json.utf8))
    }

    private func item(_ id: String, _ shape: String, slot: String, event: String, metric: String, threshold: Int) -> String {
        #"{"id":"\#(id)","slot":"\#(slot)","shape":"\#(shape)","status":"live","earn":{"path":"event","event":"\#(event)","metric":"\#(metric)","threshold":\#(threshold)}}"#
    }

    /// November and December, with December's three pieces and a showcase in November.
    private func twoMonthCatalog() throws -> UnlockCatalog {
        let json = """
        {"version":1,"events":[
          {"id":"thanksgiving-2026","title":"Thanksgiving","monthName":"November","startsOn":"2026-11-01","endsBefore":"2026-12-01","showcase":["harvest_gourd","pumpkin_pie","cornucopia"]},
          {"id":"winter-lights-2026","title":"Winter Lights","monthName":"December","startsOn":"2026-12-01","endsBefore":"2027-01-01","showcase":["candy_cane","gift_box","winter_hat"]}
        ],"items":[
          \(item("harvest_gourd", "harvest_gourd", slot: "carry", event: "thanksgiving-2026", metric: "visits", threshold: 1)),
          \(item("pumpkin_pie", "pumpkin_pie", slot: "carry", event: "thanksgiving-2026", metric: "climbs", threshold: 1)),
          \(item("cornucopia", "cornucopia", slot: "carry", event: "thanksgiving-2026", metric: "climbs", threshold: 5)),
          \(item("roast_turkey", "roast_turkey", slot: "carry", event: "thanksgiving-2026", metric: "steps", threshold: 10000)),
          \(item("candy_cane", "candy_cane", slot: "carry", event: "winter-lights-2026", metric: "visits", threshold: 1)),
          \(item("gift_box", "gift_box", slot: "carry", event: "winter-lights-2026", metric: "climbs", threshold: 1)),
          \(item("winter_hat", "winter_hat", slot: "head", event: "winter-lights-2026", metric: "climbs", threshold: 3))
        ]}
        """
        return try JSONDecoder().decode(UnlockCatalog.self, from: Data(json.utf8))
    }

    @Test
    func theEventWhoseWindowHoldsTodayIsTheOneShown() throws {
        let catalog = try twoMonthCatalog()

        guard case .running(let november) = OnboardingMonthlyEvent.resolve(catalog: catalog, now: date(2026, 11, 4), calendar: calendar) else {
            Issue.record("expected the November event to be running"); return
        }
        #expect(november.event.id == "thanksgiving-2026")
        #expect(november.piecesToEarn == 4)
        #expect(november.daysLeft == 27)

        guard case .running(let december) = OnboardingMonthlyEvent.resolve(catalog: catalog, now: date(2026, 12, 1, hour: 0), calendar: calendar) else {
            Issue.record("expected December's event the moment it opens"); return
        }
        #expect(december.event.id == "winter-lights-2026")
        guard case .running(let lastDay) = OnboardingMonthlyEvent.resolve(catalog: catalog, now: date(2026, 11, 30, hour: 23), calendar: calendar) else {
            Issue.record("expected November to run through its last day"); return
        }
        #expect(lastDay.event.id == "thanksgiving-2026")
        #expect(lastDay.daysLeft == 1)
    }

    @Test
    func theFirstPieceIsLabelledYoursTodayAndTheRestSayWhatTheyTake() throws {
        guard case .running(let running) = OnboardingMonthlyEvent.resolve(catalog: try twoMonthCatalog(), now: date(2026, 11, 4), calendar: calendar) else {
            Issue.record("no running event"); return
        }
        #expect(running.pieces.map(\.label) == ["YOURS TODAY", "1 CLIMB", "5 CLIMBS"])
        #expect(running.pieces.map(\.gear) == [.harvestGourd, .pumpkinPie, .cornucopia])
    }

    @Test
    func anEventThatStartsWithinSevenDaysIsComingSoonAndNotBefore() throws {
        // With November gone and December not yet open, the week before it is coming soon.
        // Run the clock against a catalogue with that gap.
        let gapped = try JSONDecoder().decode(UnlockCatalog.self, from: Data("""
        {"version":1,"events":[
          {"id":"winter-lights-2026","title":"Winter Lights","monthName":"December","startsOn":"2026-12-01","endsBefore":"2027-01-01","showcase":["candy_cane","gift_box","winter_hat"]}
        ],"items":[
          \(item("candy_cane", "candy_cane", slot: "carry", event: "winter-lights-2026", metric: "visits", threshold: 1)),
          \(item("gift_box", "gift_box", slot: "carry", event: "winter-lights-2026", metric: "climbs", threshold: 1)),
          \(item("winter_hat", "winter_hat", slot: "head", event: "winter-lights-2026", metric: "climbs", threshold: 3))
        ]}
        """.utf8))
        guard case .comingSoon(let soon) = OnboardingMonthlyEvent.resolve(catalog: gapped, now: date(2026, 11, 24), calendar: calendar) else {
            Issue.record("expected coming soon seven days out"); return
        }
        #expect(soon.event.id == "winter-lights-2026")
        #expect(soon.pieces.map(\.label) == Array(repeating: "OPENS DEC 1", count: 3))

        #expect(OnboardingMonthlyEvent.resolve(catalog: gapped, now: date(2026, 11, 23), calendar: calendar) == .neutral, "eight days out is too early to announce")
    }

    @Test
    func aFinishedEventIsNeverShownAndAnEmptyMonthIsNeutral() throws {
        let catalog = try twoMonthCatalog()

        #expect(OnboardingMonthlyEvent.resolve(catalog: catalog, now: date(2027, 1, 20), calendar: calendar) == .neutral)
        #expect(OnboardingMonthlyEvent.resolve(catalog: catalog, now: date(2026, 10, 1), calendar: calendar) == .neutral, "an event that has not opened and is not within a week stays quiet")
        #expect(OnboardingMonthlyEvent.resolve(catalog: .empty, now: date(2026, 11, 4), calendar: calendar) == .neutral)
    }

    @Test
    func aRunningEventSaysEverythingFromTheCatalogue() throws {
        let presentation = OnboardingMonthlyEvent.resolve(catalog: try twoMonthCatalog(), now: date(2026, 11, 4), calendar: calendar)
        let content = ThisMonthEventContent(
            presentation: presentation, landmarkCount: 40,
            usualClimbSteps: 1_800, usualClimbMinutes: 22,
            weeklyTarget: WeeklyTarget(days: 3), calendar: calendar
        )

        #expect(content.kicker == "THIS MONTH")
        #expect(content.headlineLines == ["Thanksgiving", "is on."])
        #expect(content.subline == "Climb this November and earn gear for your athlete. Everyone can earn every piece.")
        #expect(content.tiles == [
            .init(value: "4", label: "PIECES TO EARN"),
            .init(value: "27", label: "DAYS LEFT"),
            .init(value: "3×", label: "A WEEK")
        ])
        #expect(content.fineLine == "Ends Nov 30. A new event opens every month.")
    }

    @Test
    func theTargetTileAppearsOnlyWhenATargetWasSet() throws {
        let presentation = OnboardingMonthlyEvent.resolve(catalog: try twoMonthCatalog(), now: date(2026, 11, 4), calendar: calendar)
        let content = ThisMonthEventContent(
            presentation: presentation, landmarkCount: nil, usualClimbSteps: nil, usualClimbMinutes: nil,
            weeklyTarget: nil, calendar: calendar
        )
        #expect(content.tiles.map(\.label) == ["PIECES TO EARN", "DAYS LEFT"])
    }

    @Test
    func theNeutralVersionHasNoGearAndNothingDated() throws {
        let content = ThisMonthEventContent(
            presentation: .neutral, landmarkCount: 40,
            usualClimbSteps: 1_800, usualClimbMinutes: 22,
            weeklyTarget: nil, calendar: calendar
        )

        #expect(content.kicker == "EVERY CLIMB COUNTS")
        #expect(content.headlineLines == ["You're ready", "to climb."])
        #expect(content.subline == "Pick any of 40 real landmarks. Every climb lands on its board and counts toward your records.")
        #expect(content.pieces.isEmpty)
        #expect(content.fineLine == nil)
        #expect(content.tiles == [.init(value: "1,800", label: "STEPS A CLIMB"), .init(value: "22m", label: "EACH CLIMB")])
    }

    @Test
    func theNeutralVersionDropsALandmarkCountItDoesNotHave() {
        let content = ThisMonthEventContent(
            presentation: .neutral, landmarkCount: nil, usualClimbSteps: nil, usualClimbMinutes: nil,
            weeklyTarget: nil, calendar: calendar
        )
        #expect(content.subline == "Pick any real landmark. Every climb lands on its board and counts toward your records.")
        #expect(content.tiles.isEmpty)
    }

    @Test
    func theComingSoonVersionDatesItsKickerAndItsSubline() throws {
        let gapped = try JSONDecoder().decode(UnlockCatalog.self, from: Data("""
        {"version":1,"events":[
          {"id":"winter-lights-2026","title":"Winter Lights","monthName":"December","startsOn":"2026-12-01","endsBefore":"2027-01-01"}
        ],"items":[
          \(item("candy_cane", "candy_cane", slot: "carry", event: "winter-lights-2026", metric: "visits", threshold: 1))
        ]}
        """.utf8))
        let content = ThisMonthEventContent(
            presentation: OnboardingMonthlyEvent.resolve(catalog: gapped, now: date(2026, 11, 26), calendar: calendar),
            landmarkCount: nil, usualClimbSteps: nil, usualClimbMinutes: nil, weeklyTarget: nil, calendar: calendar
        )

        #expect(content.kicker == "COMING DEC 1")
        #expect(content.headlineLines == ["Winter Lights", "starts soon."])
        #expect(content.subline == "Gear for your athlete opens on Dec 1. Climb now and you're ready for it.")
    }

    /// The copy rules: no em dash, and none of the words the brand keeps out of onboarding.
    @Test
    func noOnboardingSetupStringUsesABannedWord() throws {
        var strings: [String] = UsualClimbChoice.allCases.flatMap { [$0.title, $0.detail] }
        strings.append(OnboardingCityClaimCopy.introduction)
        strings.append("Set a target if you want one. Hit your days and close your week.")
        strings.append("Change any of it in Settings.")

        let catalog = try twoMonthCatalog()
        let running = OnboardingMonthlyEvent.resolve(catalog: catalog, now: date(2026, 11, 4), calendar: calendar)
        for presentation in [running, OnboardingMonthlyEvent.neutral] {
            let content = ThisMonthEventContent(
                presentation: presentation, landmarkCount: 12, usualClimbSteps: 1_000, usualClimbMinutes: 12,
                weeklyTarget: WeeklyTarget(days: 3), calendar: calendar
            )
            strings.append(content.kicker)
            strings.append(content.subline)
            strings.append(contentsOf: content.headlineLines)
            strings.append(contentsOf: content.tiles.map(\.label))
            if let fineLine = content.fineLine { strings.append(fineLine) }
        }

        for string in strings {
            let lowered = string.lowercased()
            #expect(!string.contains("\u{2014}"), "\(string)")
            #expect(!lowered.contains("race"), "\(string)")
            #expect(!lowered.contains(" live"), "\(string)")
            #expect(!lowered.contains("field"), "\(string)")
        }
    }
}
