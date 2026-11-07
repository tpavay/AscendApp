import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import AscendApp

/// Screen 08, the profile screen, with no view: what the climber's own leaderboard row says as they
/// type, the age a birthday gives, the unit conversions behind the ruler and the scale, what a
/// Skip leaves behind, and what the sign-in hand-off carries to the account.
@MainActor
struct OnboardingProfileSetupTests {
    private let utc = TimeZone(secondsFromGMT: 0) ?? .gmt
    private let english = Locale(identifier: "en_US")

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .distantPast
    }

    private func draft(system: MeasurementSystem = .imperial) -> ProfileSetupDraft {
        ProfileSetupDraft(answers: PreAuthOnboardingAnswers(), system: system)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "profile-setup-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    // MARK: - The leaderboard row

    @Test
    func anEmptyProfileReadsAsTheNameSignInPublishesAndShowsNoSubline() {
        let empty = draft()
        #expect(SignInNamePlaceholder.boardName == "CHANGE ME")

        #expect(empty.displayName == "CHANGE ME")
        #expect(empty.initials == "CM")
        #expect(empty.subline(on: date(2026, 11, 4), calendar: calendar) == nil, "hidden while nothing is set")
        #expect(empty.birthdayRowText(calendar: calendar, locale: english) == nil)
        #expect(empty.heightRowText == nil)
        #expect(empty.weightRowText == nil)
    }

    @Test
    func theRowFollowsEveryKeystrokeAndTheInitialsFollowTheName() {
        var typing = draft()

        typing.firstName = "t"
        #expect(typing.displayName == "t")
        #expect(typing.initials == "T", "one name, one initial")

        typing.firstName = "tyler"
        typing.lastName = "pavay"
        #expect(typing.displayName == "tyler pavay", "shown as typed")
        #expect(typing.initials == "TP")

        typing.firstName = ""
        #expect(typing.displayName == "pavay")
        #expect(typing.initials == "P")

        typing.lastName = "   "
        #expect(typing.displayName == "CHANGE ME", "spaces are not a name")
        #expect(typing.initials == "CM")
    }

    @Test
    func theRowPreviewsExactlyWhatSignInPublishes() {
        var typing = draft()

        typing.firstName = "Tyler"
        #expect(typing.boardName == "Tyler")
        #expect(typing.displayName == "Tyler", "one name is a whole name")
        #expect(!typing.isNameRefused)

        typing.firstName = "Fuck"
        #expect(typing.boardName == nil)
        #expect(typing.isNameRefused)
        #expect(typing.displayName == "CHANGE ME", "a refused name is never previewed as accepted")
        #expect(typing.initials == "CM")

        typing.firstName = ""
        #expect(!typing.isNameRefused, "nothing typed is nothing refused")
        #expect(typing.displayName == "CHANGE ME")
    }

    @Test
    func aRestoredRefusedNameIsCaughtWithoutATouch() {
        var answers = PreAuthOnboardingAnswers()
        answers.firstName = "Fuck"

        #expect(ProfileSetupDraft(answers: answers, system: .imperial).isNameRefused)
    }

    @Test
    func theTwoFieldsCannotComposeANameThePolicyRefusesForLength() {
        let long = String(repeating: "ab", count: 40)

        #expect(ProfileSetupDraft.cappedName(long, beside: "").count == DisplayNamePolicy.maximumLength)

        let first = ProfileSetupDraft.cappedName(String(repeating: "ab", count: 25), beside: "")
        let last = ProfileSetupDraft.cappedName(long, beside: first)
        #expect(first.count == 50)
        #expect(last.count == 29, "the 50 beside it and the space between")
        #expect(DisplayNamePolicy.isAllowed("\(first) \(last)"))

        #expect(ProfileSetupDraft.cappedName("x", beside: long).isEmpty, "a full field leaves no room")
        #expect(ProfileSetupDraft.cappedName("Tyler", beside: "Pavay") == "Tyler", "a name that fits is untouched")
    }

    @Test
    func theSublineReadsGenderThenAgeAndNeverTheBirthday() {
        let today = date(2026, 11, 4)
        var filled = draft()
        filled.gender = .man
        filled.birthday = PreAuthOnboardingBirthday(year: 1996, month: 6, day: 14)

        #expect(filled.subline(on: today, calendar: calendar) == "M \u{00B7} 30")

        filled.gender = .woman
        #expect(filled.subline(on: today, calendar: calendar) == "F \u{00B7} 30")
        filled.gender = .nonBinary
        #expect(filled.subline(on: today, calendar: calendar) == "Other \u{00B7} 30")
        filled.gender = .preferNotToSay
        #expect(filled.subline(on: today, calendar: calendar) == "30", "Private shows nothing")

        filled.gender = nil
        filled.birthday = nil
        #expect(filled.subline(on: today, calendar: calendar) == nil)

        filled.gender = .man
        #expect(filled.subline(on: today, calendar: calendar) == "M", "gender alone, the birthday row not set")
    }

    @Test
    func theSublineAddsTheCityOnceTheNextStepHasClaimedOne() {
        var answers = PreAuthOnboardingAnswers()
        answers.gender = .woman
        answers.city = PreAuthOnboardingCity(city: "Denver", region: "CO", countryCode: "US", countryName: "United States")

        #expect(ProfileSetupDraft(answers: answers, system: .imperial).subline() == "F \u{00B7} Denver")
    }

    @Test
    func theBirthdayRowShowsTheDateAndAgeButNoOutwardTextCarriesTheDate() {
        var filled = draft()
        filled.birthday = PreAuthOnboardingBirthday(year: 1996, month: 6, day: 14)
        let today = date(2026, 11, 4)

        #expect(filled.birthdayRowText(on: today, calendar: calendar, locale: english) == "Jun 14, 1996 \u{00B7} 30")
        #expect(filled.subline(on: today, calendar: calendar)?.contains("1996") == false)
        #expect(filled.displayName.contains("1996") == false)
    }

    @Test
    func aBirthdayOutsideThirteenToNinetyNineShowsNoAgeAndIsNotKept() {
        var young = draft()
        young.birthday = PreAuthOnboardingBirthday(year: 2020, month: 1, day: 1)

        #expect(young.age(on: date(2026, 11, 4), calendar: calendar) == nil)
        #expect(young.birthdayRowText(on: date(2026, 11, 4), calendar: calendar, locale: english) == nil)
    }

    // MARK: - Age

    @Test
    func aBirthdayGivesTheAgeOnTheDayItIsReached() {
        var card = draft()
        card.birthday = PreAuthOnboardingBirthday(year: 1998, month: 11, day: 5)

        #expect(card.age(on: date(2026, 11, 4), calendar: calendar) == 27)
        #expect(card.age(on: date(2026, 11, 5), calendar: calendar) == 28)
    }

    @Test
    func theWheelOffersOnlyBirthdaysThatGiveAnAcceptedAge() {
        let today = date(2026, 11, 4)
        let range = ProfileSetupDraft.birthdayRange(on: today, calendar: calendar)

        var youngest = draft()
        youngest.setBirthday(from: range.upperBound, calendar: calendar)
        #expect(youngest.age(on: today, calendar: calendar) == 13)

        var oldest = draft()
        oldest.setBirthday(from: range.lowerBound, calendar: calendar)
        #expect(oldest.age(on: today, calendar: calendar) == 99)
    }

    /// A phone in Thailand or set to the Japanese calendar still stores 1993, or the rules refuse
    /// the write, or the age check drops a birthday the climber chose.
    @Test(arguments: [Calendar.Identifier.buddhist, .japanese])
    func aBirthdayIsGregorianWhateverCalendarThePhoneUses(identifier: Calendar.Identifier) {
        var device = Calendar(identifier: identifier)
        device.timeZone = utc
        let today = date(2026, 11, 4)
        let born = date(1993, 3, 15)

        var card = draft()
        card.setBirthday(from: born, calendar: device)

        #expect(card.birthday == PreAuthOnboardingBirthday(year: 1993, month: 3, day: 15))
        #expect(card.age(on: today, calendar: device) == 33)
        #expect(card.birthdayDate(calendar: device) == born)
        #expect(ProfileSetupDraft.birthdayRange(on: today, calendar: device) == ProfileSetupDraft.birthdayRange(on: today, calendar: calendar))
        #expect(ProfileSetupDraft.wheelStart(on: today, calendar: device) == ProfileSetupDraft.wheelStart(on: today, calendar: calendar))
    }

    // MARK: - Defaults are never saved

    @Test
    func openingASheetOnItsTypicalValueSavesNothing() {
        // A sheet opens at a typical value when nothing is set. The draft has no value until the
        // sheet's Done hands one back, so reading the opening value changes nothing.
        let untouched = draft()

        #expect(ProfileHeightSheet.mark(forCentimeters: untouched.heightCm, system: .imperial) == ProfileMeasures.typicalHeightInches)
        #expect(ProfileHeightSheet.mark(forCentimeters: untouched.heightCm, system: .metric) == ProfileMeasures.typicalHeightCentimeters)
        #expect(ProfileWeightSheet.step(forKilograms: untouched.weightKg, system: .imperial) == ProfileMeasures.typicalWeightPounds)
        #expect(ProfileWeightSheet.step(forKilograms: untouched.weightKg, system: .metric) == ProfileMeasures.typicalWeightHalfKilograms)
        #expect(untouched.heightCm == nil)
        #expect(untouched.weightKg == nil)
        #expect(untouched.birthday == nil)

        var answers = PreAuthOnboardingAnswers()
        untouched.apply(to: &answers)
        #expect(answers == PreAuthOnboardingAnswers(), "Continue on an untouched screen writes nothing")
    }

    @Test
    func aSheetOpensWhereTheStoredValueIs() {
        #expect(ProfileHeightSheet.mark(forCentimeters: 177.8, system: .imperial) == 70)
        #expect(ProfileHeightSheet.mark(forCentimeters: 177.8, system: .metric) == 178)
        #expect(ProfileWeightSheet.step(forKilograms: 79.37866, system: .imperial) == 175)
        #expect(ProfileWeightSheet.step(forKilograms: 79.5, system: .metric) == 159)
    }

    @Test
    func doneStoresCentimetresAndKilogramsWhateverTheUnit() {
        #expect(abs(ProfileHeightSheet.centimeters(forMark: 70, system: .imperial) - 177.8) < 0.001)
        #expect(ProfileHeightSheet.centimeters(forMark: 178, system: .metric) == 178)
        #expect(abs(ProfileWeightSheet.kilograms(forStep: 175, system: .imperial) - 79.379) < 0.001)
        #expect(ProfileWeightSheet.kilograms(forStep: 159, system: .metric) == 79.5)
    }

    // MARK: - Units

    @Test
    func heightAndWeightReadTheSameInEitherUnit() {
        var stored = PreAuthOnboardingAnswers()
        stored.heightCm = 177.8
        stored.weightKg = 79.37866

        let imperial = ProfileSetupDraft(answers: stored, system: .imperial)
        let metric = ProfileSetupDraft(answers: stored, system: .metric)

        #expect(imperial.heightRowText == "5'10\"")
        #expect(imperial.weightRowText == "175 lb")
        #expect(metric.heightRowText == "178 cm")
        #expect(metric.weightRowText == "79.5 kg")
    }

    @Test
    func theRangesAreTheDesignsAndNothingEscapesThem() {
        #expect(ProfileMeasures.heightInchesRange == 48...90, "4'0\" to 7'6\"")
        #expect(ProfileMeasures.heightCentimetersRange == 122...229)
        #expect(ProfileMeasures.weightPoundsRange == 70...400)
        #expect(ProfileMeasures.weightHalfKilogramsRange == 64...362, "32 to 181 kg")

        #expect(ProfileMeasures.inches(centimeters: 80) == 48)
        #expect(ProfileMeasures.inches(centimeters: 300) == 90)
        #expect(ProfileMeasures.pounds(kilograms: 20) == 70)
        #expect(ProfileMeasures.pounds(kilograms: 300) == 400)
        #expect(ProfileMeasures.halfKilograms(kilograms: 10) == 64)
    }

    @Test
    func switchingUnitKeepsTheSameHeightAndWeightWithinOneStep() {
        for inches in ProfileMeasures.heightInchesRange {
            let centimeters = ProfileMeasures.switchHeight(inches: inches)
            #expect(abs(Double(centimeters) - Double(inches) * 2.54) <= 0.5)
            #expect(abs(ProfileMeasures.switchHeight(centimeters: centimeters) - inches) <= 1)
        }

        for pounds in ProfileMeasures.weightPoundsRange {
            let half = ProfileMeasures.switchWeight(pounds: pounds)
            // Half a kilogram is the step, except at the top, where 400 lb is 181.4 kg and the scale ends at 181.
            let atAnEnd = !(ProfileMeasures.weightHalfKilogramsRange.lowerBound + 1 ..< ProfileMeasures.weightHalfKilogramsRange.upperBound).contains(half)
            #expect(abs(ProfileMeasures.kilograms(halfKilograms: half) - ProfileMeasures.kilograms(pounds: pounds)) <= (atAnEnd ? 0.5 : 0.25))
            #expect(abs(ProfileMeasures.switchWeight(halfKilograms: half) - pounds) <= 1)
        }

        #expect(ProfileMeasures.switchHeight(inches: 70) == 178)
        #expect(ProfileMeasures.switchWeight(pounds: 175) == 159, "79.4 kg snaps to 79.5")
    }

    @Test
    func theReadoutsUseRealPrimeMarksAndOneDecimal() {
        #expect(ProfileMeasures.rulerReadout(inches: 70) == "5\u{2032}10\u{2033}")
        #expect(ProfileMeasures.kilogramText(79.37866) == "79.4")
        #expect(ProfileMeasures.kilogramText(80) == "80")
    }

    @Test
    func aUnitSwitchedInASheetIsTheAppsUnitFromThenOn() {
        let suite = "profile-units-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let settings = SettingsManager(userDefaults: defaults)
        settings.measurementSystem = .imperial
        var card = draft(system: settings.measurementSystem)

        OnboardingProfileSetupScreen.switchUnit(to: .metric, in: &card, settings: settings)

        #expect(card.system == .metric)
        #expect(settings.measurementSystem == .metric, "one setting, so later screens agree")
        #expect(SettingsManager(userDefaults: defaults).measurementSystem == .metric, "it survives a relaunch")
    }

    // MARK: - Height class

    @Test(arguments: [
        (laidOut: 759.0, top: 59.0, bottom: 34.0, phone: "iPhone 16", compact: false),
        (laidOut: 778.0, top: 62.0, bottom: 34.0, phone: "iPhone 17 Pro", compact: false),
        (laidOut: 763.0, top: 47.0, bottom: 34.0, phone: "iPhone 16e", compact: false),
        (laidOut: 728.0, top: 50.0, bottom: 34.0, phone: "iPhone 13 mini", compact: true),
        (laidOut: 647.0, top: 20.0, bottom: 0.0, phone: "iPhone SE", compact: true)
    ])
    func aPhoneIsCompactOnlyBelowTheHandoffsCanvas(laidOut: Double, top: Double, bottom: Double, phone: String, compact: Bool) {
        #expect(OnboardingProfileSetupScreen.isCompact(laidOutHeight: laidOut, topInset: top, bottomInset: bottom) == compact, "\(phone)")
    }

    @Test
    func theKeyboardDoesNotMakeAPhoneCompact() {
        // A 336 pt keyboard moves that height from the laid-out size into the bottom inset.
        #expect(!OnboardingProfileSetupScreen.isCompact(laidOutHeight: 759 - 302, topInset: 59, bottomInset: 34 + 302))
    }

    // MARK: - Gender

    @Test
    func theFourSegmentsNameEachChoiceAndPrivateShowsNothing() {
        #expect(ProfileSetupDraft.genderChoices.map(\.title) == ["Male", "Female", "Other", "Private"])
        #expect(ProfileSetupDraft.genderChoices.map(\.gender) == [.man, .woman, .nonBinary, .preferNotToSay])
        #expect(draft().gender == nil, "nothing preselected")
    }

    @Test
    func aTapOnTheChosenSegmentClearsItAgain() {
        var answers = PreAuthOnboardingAnswers()
        answers.gender = .man
        var card = ProfileSetupDraft(answers: answers, system: .imperial)
        card.gender = nil
        card.apply(to: &answers)

        #expect(answers.gender == nil)
    }

    // MARK: - Saving and Skip

    @Test
    func continuingWritesTheProfileAndAnEmptyOneWritesNothing() {
        var answers = PreAuthOnboardingAnswers()
        draft().apply(to: &answers)
        #expect(answers == PreAuthOnboardingAnswers())

        var card = draft()
        card.firstName = "  Tyler "
        card.lastName = "Pavay"
        card.photoFileName = "photo-1.jpg"
        card.gender = .woman
        card.birthday = PreAuthOnboardingBirthday(year: 1990, month: 6, day: 15)
        card.heightCm = 170
        card.apply(to: &answers)

        #expect(answers.firstName == "Tyler", "trimmed")
        #expect(answers.lastName == "Pavay")
        #expect(answers.profilePhotoFileName == "photo-1.jpg")
        #expect(answers.gender == .woman)
        #expect(answers.birthday == PreAuthOnboardingBirthday(year: 1990, month: 6, day: 15))
        #expect(answers.heightCm == 170)
        #expect(answers.weightKg == nil)
    }

    @Test
    func aNameCleanedToNothingIsNotStored() {
        var answers = PreAuthOnboardingAnswers()
        answers.firstName = "Old"
        var card = ProfileSetupDraft(answers: answers, system: .imperial)
        card.firstName = "   "
        card.apply(to: &answers)

        #expect(answers.firstName == nil)
    }

    private func coordinator(
        _ configure: (inout PreAuthOnboardingAnswers) -> Void = { _ in },
        photos: OnboardingProfilePhotoStore
    ) -> OnboardingV3Coordinator {
        let suite = "onboarding-v3-profile-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let coordinator = OnboardingV3Coordinator(
            store: PreAuthOnboardingStore(userDefaults: defaults),
            photos: photos,
            startingAt: .profileSetup
        )
        coordinator.update(configure)
        return coordinator
    }

    private func jpegData(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    @Test
    func skippingLeavesNothingSetAndClearsAnEarlierPassIncludingThePhoto() throws {
        let photos = OnboardingProfilePhotoStore(directory: temporaryDirectory())
        let name = try #require(photos.save(try jpegData(width: 64, height: 64)))
        let coordinator = coordinator({
            $0.firstName = "Tyler"
            $0.lastName = "Pavay"
            $0.profilePhotoFileName = name
            $0.gender = .woman
            $0.birthday = PreAuthOnboardingBirthday(year: 1990, month: 6, day: 15)
            $0.heightCm = 170
            $0.weightKg = 70
            $0.usualClimbSteps = 1_800
        }, photos: photos)

        OnboardingProfileSetupScreen.skip(coordinator, photos: photos)

        #expect(coordinator.answers.firstName == nil)
        #expect(coordinator.answers.lastName == nil)
        #expect(coordinator.answers.profilePhotoFileName == nil)
        #expect(coordinator.answers.gender == nil)
        #expect(coordinator.answers.birthday == nil)
        #expect(coordinator.answers.heightCm == nil)
        #expect(coordinator.answers.weightKg == nil)
        #expect(coordinator.answers.usualClimbSteps == 1_800, "other screens' answers stay")
        #expect(coordinator.step == .claimCity)
        #expect(photos.url(for: name) == nil, "the picture leaves the device with the answer")
    }

    @Test
    func signingOutDropsTheNameAndThePhotoSoTheNextAccountCannotReceiveThem() throws {
        let photos = OnboardingProfilePhotoStore(directory: temporaryDirectory())
        let name = try #require(photos.save(try jpegData(width: 64, height: 64)))
        let coordinator = coordinator({
            $0.firstName = "Tyler"
            $0.lastName = "Pavay"
            $0.profilePhotoFileName = name
        }, photos: photos)

        coordinator.sessionEnded()

        #expect(coordinator.answers.firstName == nil)
        #expect(coordinator.answers.profilePhotoFileName == nil)
        #expect(photos.url(for: name) == nil)
    }

    // MARK: - The photo held on the device

    @Test
    func aPickedPhotoIsRedrawnAtACappedSizeAsAJPEG() throws {
        let photos = OnboardingProfilePhotoStore(directory: temporaryDirectory())
        let name = try #require(photos.save(try jpegData(width: 3_000, height: 2_000)))

        let stored = try #require(photos.data(for: name))
        let source = try #require(CGImageSourceCreateWithData(stored as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)

        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let width = try #require(properties[kCGImagePropertyPixelWidth] as? Int)
        let height = try #require(properties[kCGImagePropertyPixelHeight] as? Int)
        #expect(max(width, height) == OnboardingProfilePhotoStore.maximumPixelSize)
        #expect(properties[kCGImagePropertyGPSDictionary] == nil, "no location leaves with the picture")
    }

    @Test
    func somethingThatIsNotAPictureIsRefusedAndEachPhotoGetsItsOwnName() throws {
        let photos = OnboardingProfilePhotoStore(directory: temporaryDirectory())
        #expect(photos.save(Data("not a picture".utf8)) == nil)

        let png = try jpegData(width: 32, height: 32)
        let first = try #require(photos.save(png))
        let second = try #require(photos.save(png))
        #expect(first != second, "a new name is what redraws the avatar")

        photos.remove(keeping: second)
        #expect(photos.url(for: first) == nil)
        #expect(photos.url(for: second) != nil)
        #expect(photos.url(for: "../escape.jpg") == nil)
    }

    // MARK: - What the sign-in hand-off carries

    private func existingProfile(_ fields: [String: Any]) -> UserDisplayNameData {
        UserDisplayNameData(fields)
    }

    private func answersWithName() -> PreAuthOnboardingAnswers {
        var answers = PreAuthOnboardingAnswers()
        answers.firstName = "Tyler"
        answers.lastName = "Pavay"
        answers.profilePhotoFileName = "photo-1.jpg"
        return answers
    }

    @Test
    func theTypedNameAndPhotoFillABlankProfile() {
        let fill = OnboardingProfileFill.plan(answers: answersWithName(), existing: nil)

        #expect(fill.name == .init(firstName: "Tyler", lastName: "Pavay"))
        #expect(fill.photoFileName == "photo-1.jpg")
        #expect(!fill.isEmpty)
        #expect(!fill.hasDemographics, "a name and a photo are not demographics")
    }

    @Test
    func theTypedNameReplacesOnlyThePlaceholderSignInWrote() {
        let placeholder = existingProfile(["firstName": "CHANGE", "lastName": "ME", "displayName": "CHANGE ME"])
        #expect(OnboardingProfileFill.plan(answers: answersWithName(), existing: placeholder).name != nil)

        let real = existingProfile(["firstName": "Ava", "lastName": "Mills", "displayName": "Ava Mills"])
        #expect(OnboardingProfileFill.plan(answers: answersWithName(), existing: real).name == nil, "a real name is never overwritten")

        let legacy = existingProfile(["displayName": "Mason D."])
        #expect(OnboardingProfileFill.plan(answers: answersWithName(), existing: legacy).name == nil)
    }

    @Test
    func anAccountThatAlreadyHasAPhotoKeepsIt() {
        let withPhoto = existingProfile(["profilePictureURL": "https://example.com/p.jpg"])

        #expect(OnboardingProfileFill.plan(answers: answersWithName(), existing: withPhoto).photoFileName == nil)
    }

    @Test
    func oneHalfOfANameIsAWholeNameEitherWay() throws {
        var first = answersWithName()
        first.lastName = nil
        #expect(OnboardingProfileFill.plan(answers: first, existing: nil).name == .init(firstName: "Tyler", lastName: ""))

        var last = answersWithName()
        last.firstName = nil
        let name = try #require(OnboardingProfileFill.plan(answers: last, existing: nil).name)
        #expect(name == .init(firstName: "", lastName: "Pavay"))
        #expect(try DisplayNamePolicy.typedBoardName(firstName: name.firstName, lastName: name.lastName) == "Pavay")
    }

    /// What the write leaves on the profile has to read back as that one name, not as a blank
    /// profile the next run would fill again, and has to keep the placeholder check honest.
    @Test
    func aStoredSingleNameReadsBackAsThatNameAndIsNeverReplaced() {
        let stored = existingProfile(["firstName": "Tyler", "lastName": "", "displayName": "Tyler"])

        #expect(stored.resolvedDisplayName == "Tyler")

        var other = PreAuthOnboardingAnswers()
        other.firstName = "Ava"
        other.lastName = "Mills"
        #expect(OnboardingProfileFill.plan(answers: other, existing: stored).name == nil)
    }

    @Test
    func anObjectionableNameIsLeftOutAndNeverBlocksTheRest() {
        var rude = answersWithName()
        rude.firstName = "Fuck"
        rude.gender = .woman
        let fill = OnboardingProfileFill.plan(answers: rude, existing: nil)
        #expect(fill.name == nil)
        #expect(fill.gender == .woman)
    }

    @Test
    func theHandOffDropsTheNameAndPhotoOnceTheyLand() async throws {
        let suite = "profile-handoff-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let store = PreAuthOnboardingStore(userDefaults: defaults)
        let photos = OnboardingProfilePhotoStore(directory: temporaryDirectory())
        let name = try #require(photos.save(try jpegData(width: 64, height: 64)))
        var answers = answersWithName()
        answers.profilePhotoFileName = name
        store.save(answers)

        var written: [OnboardingProfileFill] = []
        let handOff = OnboardingV3SignInHandOff(
            seams: .init(
                isProfileWriteEnabled: { true },
                signInNameSettled: {},
                readProfile: { _ in nil },
                writeProfile: { _, _, fill in written.append(fill) },
                recordProfileStepFailure: { _ in },
                importHealthHistory: { _ in true },
                markPostSignInOnboardingComplete: {},
                deviceWeeklyTarget: { _ in nil },
                saveWeeklyTarget: { _, _ in },
                reconcileWeeklyTarget: { _ in }
            ),
            store: store,
            intent: OnboardingV3HandOffIntent(userDefaults: defaults),
            photos: photos
        )

        let outcome = await handOff.runAfterSignIn(userId: "u1", email: nil)

        #expect(outcome == .complete)
        #expect(written.first?.name == .init(firstName: "Tyler", lastName: "Pavay"))
        #expect(written.first?.photoFileName == name)
        #expect(store.answers().firstName == nil)
        #expect(store.answers().profilePhotoFileName == nil)
        #expect(photos.url(for: name) == nil, "uploaded or not needed, the picture is done with the device")
    }

    /// The account a hand-off writes to, standing in for Firestore: whoever commits last holds it.
    @MainActor
    private final class FakeAccount {
        var name: OnboardingProfileFill.Name?
        var written: [OnboardingProfileFill] = []

        var profile: UserDisplayNameData? {
            name.map {
                UserDisplayNameData([
                    "firstName": $0.firstName,
                    "lastName": $0.lastName,
                    "displayName": [$0.firstName, $0.lastName].filter { !$0.isEmpty }.joined(separator: " ")
                ])
            }
        }
    }

    private func handOff(
        answers: PreAuthOnboardingAnswers,
        account: FakeAccount,
        signInNameSettled: @escaping @MainActor () async -> Void = {}
    ) -> (OnboardingV3SignInHandOff, PreAuthOnboardingStore) {
        let suite = "profile-handoff-order-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let store = PreAuthOnboardingStore(userDefaults: defaults)
        store.save(answers)
        let handOff = OnboardingV3SignInHandOff(
            seams: .init(
                isProfileWriteEnabled: { true },
                signInNameSettled: signInNameSettled,
                readProfile: { _ in account.profile },
                writeProfile: { _, _, fill in
                    account.written.append(fill)
                    if let name = fill.name { account.name = name }
                },
                recordProfileStepFailure: { _ in },
                importHealthHistory: { _ in true },
                markPostSignInOnboardingComplete: {},
                deviceWeeklyTarget: { _ in nil },
                saveWeeklyTarget: { _, _ in },
                reconcileWeeklyTarget: { _ in }
            ),
            store: store,
            intent: OnboardingV3HandOffIntent(userDefaults: defaults),
            photos: OnboardingProfilePhotoStore(directory: temporaryDirectory())
        )
        return (handOff, store)
    }

    private static let placeholderName = OnboardingProfileFill.Name(
        firstName: SignInNamePlaceholder.firstName,
        lastName: SignInNamePlaceholder.lastName
    )

    /// Adoption commits the placeholder only after an Auth round trip, so the hand-off, with no such
    /// trip, used to commit first and lose the typed name for good.
    @Test
    func aTypedNameSurvivesAPlaceholderStillOnItsWay() async {
        let account = FakeAccount()
        let adoption = Task { @MainActor in
            for _ in 0..<20 { await Task.yield() }
            account.name = Self.placeholderName
        }
        let (handOff, store) = handOff(answers: answersWithName(), account: account) { await adoption.value }

        #expect(await handOff.runAfterSignIn(userId: "u1", email: nil) == .complete)

        #expect(account.name == .init(firstName: "Tyler", lastName: "Pavay"))
        #expect(store.answers().firstName == nil)
    }

    @Test
    func aTypedNameReplacesAPlaceholderAlreadyThere() async {
        let account = FakeAccount()
        account.name = Self.placeholderName
        let (handOff, _) = handOff(answers: answersWithName(), account: account)

        #expect(await handOff.runAfterSignIn(userId: "u1", email: nil) == .complete)

        #expect(account.name == .init(firstName: "Tyler", lastName: "Pavay"))
    }

    @Test
    func aNameTheProviderSuppliedWinsWheneverItLands() async {
        let provider = OnboardingProfileFill.Name(firstName: "Ava", lastName: "Mills")
        let account = FakeAccount()
        let adoption = Task { @MainActor in
            for _ in 0..<20 { await Task.yield() }
            account.name = provider
        }
        let (handOff, _) = handOff(answers: answersWithName(), account: account) { await adoption.value }

        #expect(await handOff.runAfterSignIn(userId: "u1", email: nil) == .complete)

        #expect(account.name == provider)
    }

    @Test
    func aNameTypedAloneStillHandsOffAndLeavesTheDevice() async {
        var answers = PreAuthOnboardingAnswers()
        answers.firstName = "Tyler"
        #expect(answers.carriesHandOffWork)

        let account = FakeAccount()
        let (handOff, store) = handOff(answers: answers, account: account)

        #expect(await handOff.runAfterSignIn(userId: "u1", email: nil) == .complete)

        #expect(account.name == .init(firstName: "Tyler", lastName: ""))
        #expect(store.answers().firstName == nil)
    }

    @Test
    func aRefusedNameTypedAloneWritesNothingAndStillLeavesTheDevice() async {
        var answers = PreAuthOnboardingAnswers()
        answers.firstName = "Fuck"

        let account = FakeAccount()
        let (handOff, store) = handOff(answers: answers, account: account)

        #expect(await handOff.runAfterSignIn(userId: "u1", email: nil) == .complete)

        #expect(account.written.isEmpty)
        #expect(store.answers().firstName == nil)
    }

    @Test
    func theSessionShowsTheWrittenNameAndPhotoWithoutARelaunch() async throws {
        let session = AuthenticationViewModel(observesFirebaseAuth: false)
        let url = try #require(URL(string: "https://example.com/p.jpg"))

        await session.adoptWrittenName("Tyler")
        session.adoptWrittenProfilePicture(url)

        #expect(session.displayName == "Tyler")
        #expect(session.hasRemoteDisplayName)
        #expect(session.displayPhotoURL == url)
    }

    @Test
    func aRefusedWriteKeepsTheNameAndThePhotoForTheNextRun() async throws {
        let suite = "profile-handoff-refused-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let store = PreAuthOnboardingStore(userDefaults: defaults)
        let photos = OnboardingProfilePhotoStore(directory: temporaryDirectory())
        let name = try #require(photos.save(try jpegData(width: 64, height: 64)))
        var answers = answersWithName()
        answers.profilePhotoFileName = name
        store.save(answers)

        struct Refused: Error {}
        let handOff = OnboardingV3SignInHandOff(
            seams: .init(
                isProfileWriteEnabled: { true },
                signInNameSettled: {},
                readProfile: { _ in nil },
                writeProfile: { _, _, _ in throw Refused() },
                recordProfileStepFailure: { _ in },
                importHealthHistory: { _ in true },
                markPostSignInOnboardingComplete: {},
                deviceWeeklyTarget: { _ in nil },
                saveWeeklyTarget: { _, _ in },
                reconcileWeeklyTarget: { _ in }
            ),
            store: store,
            intent: OnboardingV3HandOffIntent(userDefaults: defaults),
            photos: photos
        )

        let outcome = await handOff.retryPendingAnswers(userId: "u1", email: nil)

        #expect(outcome == .deferred)
        #expect(store.answers().firstName == "Tyler")
        #expect(photos.url(for: name) != nil)
    }
}
