import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// The share funnel, proven from the code paths a climber's taps run: the composer opening, a card
/// being chosen, a share starting, and how it ended. Each test builds a real telemetry manager over
/// an in-memory sink, so an event that never fires, or fires on a cancel, fails here.
@MainActor
struct ShareSheetAnalyticsTests {
    // MARK: - Fixtures

    /// Stands in for the clipboard, Photos, Instagram and the system share sheet, none of which a
    /// simulator test host can drive.
    final class FakeExporter: ShareSheetExporting {
        enum Sheet {
            case noWindow
            /// The sheet is up and has not reported; the test resolves it with `finishSheet`.
            case pending
        }

        var rendersCard = true
        var copySucceeds = true
        var saveSucceeds = true
        var instagramInstalled = true
        var sheet: Sheet = .pending
        private(set) var pendingCompletion: (@MainActor (String?, Bool) -> Void)?

        func renderCard(model: PresetCardModel, artwork: PresetCardArtwork) -> UIImage? {
            rendersCard ? UIImage() : nil
        }

        func renderSticker<Content: View>(_ content: Content) -> UIImage? { UIImage() }
        func loadClimbArtwork(for climb: Climb) async -> UIImage? { nil }
        func copyToClipboard(_ image: UIImage) -> Bool { copySucceeds }
        func saveToPhotos(_ image: UIImage) async -> Bool { saveSucceeds }
        func shareToInstagramStory(_ card: UIImage) -> Bool { instagramInstalled }

        func presentShareSheet(image: UIImage, completion: @escaping @MainActor (String?, Bool) -> Void) -> Bool {
            guard case .pending = sheet else { return false }
            pendingCompletion = completion
            return true
        }

        /// What UIKit does when the climber picks an activity, or dismisses the sheet.
        func finishSheet(activityType: String?, completed: Bool) {
            pendingCompletion?(activityType, completed)
            pendingCompletion = nil
        }
    }

    @MainActor
    private struct Rig {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let exporter = FakeExporter()
        let viewModel: ShareSheetViewModel
        let reporter: ShareSheetAnalyticsReporter
        let presets: PresetsViewModel
        let telemetry: TelemetryManager

        init(source: ShareSheetSource = .liveClimbSummary, climb: Climb? = .preview) {
            telemetry = makeTestTelemetry(sink: sink)
            let reporter = ShareSheetAnalyticsReporter(
                context: ShareSheetAnalyticsContext(source: source, climb: climb),
                telemetry: telemetry
            )
            self.reporter = reporter
            viewModel = ShareSheetViewModel(reporter: reporter, exporter: exporter)
            let defaults = UserDefaults(suiteName: "ShareSheetAnalyticsTests.\(UUID().uuidString)")!
            presets = PresetsViewModel(
                subject: .fixture(),
                hasTower: false,
                store: PresetPreferencesStore(defaults: defaults),
                analytics: reporter
            )
        }

        var records: [EnvelopedTelemetryRecord] { sink.records }
        var names: [String] { records.map(\.name) }

        func perform(_ action: ShareSheetViewModel.CardAction) async {
            await viewModel.perform(action, model: presets.cardModel, artwork: presets.artwork)
        }
    }

    /// What every share carries when the climber changed nothing: a zero count and every flag off.
    private static var noEditFlags: [String: TelemetryValue] {
        var flags: [String: TelemetryValue] = ["edit_count_bucket": .string("zero")]
        for kind in ShareEditKind.allCases { flags["edited_\(kind.rawValue)"] = .bool(false) }
        return flags
    }

    private func string(_ record: EnvelopedTelemetryRecord, _ key: String) -> String? {
        if case .string(let value) = record.parameters[key] { return value }
        return nil
    }

    private func flag(_ record: EnvelopedTelemetryRecord, _ key: String) -> Bool? {
        if case .bool(let value) = record.parameters[key] { return value }
        return nil
    }

    // MARK: - Event shapes

    @Test
    func theTwoActionEventsKeepTheirNamesAndCarryOnlyClosedValues() {
        let context = ShareSheetAnalyticsContext(source: .workoutDetail, climb: .preview)
        let content = ShareContent.card(layout: .splits, background: .tower)

        let tap = ShareSheetAnalyticsEvent.actionTapped(
            context: context,
            action: .story,
            content: content,
            edits: ShareEditSummary()
        ).record
        #expect(tap.name == "live_climb_share_action_tap")
        #expect(tap.destinations == [.analytics])
        #expect(tap.parameters == Self.noEditFlags.merging([
            "share_source": .string("workout_detail"),
            "action": .string("story"),
            "content_type": .string("card"),
            "card_layout": .string("splits"),
            "card_background": .string("tower"),
            "climb_id": .string("empire-state-building"),
            "climb_tier": .string("gold"),
            "climb_category": .string("skyscraper"),
            "climb_steps_bucket": .string("100_plus")
        ]) { _, new in new })

        let done = ShareSheetAnalyticsEvent.activityCompleted(
            context: context,
            action: .more,
            content: content,
            edits: ShareEditSummary(),
            destination: .messages,
            outcome: .completed
        ).record
        #expect(done.name == "live_climb_share_activity_done")
        #expect(done.parameters["destination"] == .string("messages"))
        #expect(done.parameters["outcome"] == .string("completed"))
        #expect(done.parameters["completed"] == .bool(true))
    }

    @Test
    func aClimbWithNoCatalogueEntryCarriesNoClimbParameters() {
        let context = ShareSheetAnalyticsContext(source: .loggedClimbResult, climb: nil)
        let record = ShareSheetAnalyticsEvent.composerOpened(context: context).record

        #expect(record.name == "share_composer_open")
        #expect(record.parameters == ["share_source": .string("logged_climb_result")])
    }

    @Test
    func aStickerNamesItsKindAndScopeAndNothingElse() {
        let context = ShareSheetAnalyticsContext(source: .liveClimbSummary, climb: nil)
        let record = ShareSheetAnalyticsEvent.actionTapped(
            context: context,
            action: .save,
            content: .sticker(kind: "weeklyRank", scope: .totals),
            edits: ShareEditSummary()
        ).record

        #expect(record.parameters == Self.noEditFlags.merging([
            "share_source": .string("live_climb_summary"),
            "action": .string("save"),
            "content_type": .string("sticker"),
            "sticker_kind": .string("weeklyRank"),
            "sticker_scope": .string("totals")
        ]) { _, new in new })
    }

    @Test(arguments: [
        ("com.apple.UIKit.activity.Message", ShareDestination.messages),
        ("com.apple.UIKit.activity.SaveToCameraRoll", .saveToPhotos),
        ("com.apple.UIKit.activity.CopyToPasteboard", .copy),
        ("com.apple.UIKit.activity.AirDrop", .airdrop),
        ("com.burbn.instagram.shareextension", .instagram),
        ("net.whatsapp.WhatsApp.ShareExtension", .whatsapp),
        ("com.example.SomeUnheardOfApp.share", .other),
        ("", .none)
    ])
    func anActivityTypeBucketsToAFixedSet(rawType: String, expected: ShareDestination) {
        #expect(ShareDestination(activityType: rawType) == expected)
    }

    @Test
    func aMissingActivityTypeIsNoDestination() {
        #expect(ShareDestination(activityType: nil) == .none)
    }

    // MARK: - Choosing a card

    @Test
    func swipingOntoAnotherCardReportsTheLayoutItLandedOn() {
        let rig = Rig()
        rig.presets.swipe(by: 1)

        #expect(rig.names == ["share_card_select"])
        #expect(rig.records.first.flatMap { string($0, "card_layout") } == rig.presets.currentLayout.rawValue)
    }

    @Test
    func landingOnTheCardAlreadyShowingReportsNothing() {
        let rig = Rig()
        rig.presets.select(layout: rig.presets.currentLayout)
        rig.presets.swipe(by: -1)
        #expect(rig.names.isEmpty, "Classic is first: re-selecting it and swiping back change nothing")

        rig.presets.select(layout: .rank)
        #expect(rig.names == ["share_card_select"])
    }

    @Test
    func aLayoutTheClimbCannotShowIsNotReported() {
        let rig = Rig()
        let defaults = UserDefaults(suiteName: "ShareSheetAnalyticsTests.\(UUID().uuidString)")!
        let noRank = PresetsViewModel(
            subject: .fixture(rank: nil, splits: []),
            hasTower: false,
            store: PresetPreferencesStore(defaults: defaults),
            analytics: ShareSheetAnalyticsReporter(
                context: ShareSheetAnalyticsContext(source: .workoutDetail, climb: nil),
                telemetry: rig.telemetry
            )
        )
        noRank.select(layout: .rank)

        #expect(rig.names.isEmpty)
    }

    // MARK: - Starting and finishing a share

    @Test
    func storyHandedToInstagramReportsATapThenACompletionToInstagramStories() async {
        let rig = Rig()
        await rig.perform(.story)

        #expect(rig.names == ["live_climb_share_action_tap", "live_climb_share_activity_done"])
        let done = rig.records[1]
        #expect(string(done, "action") == "story")
        #expect(string(done, "destination") == "instagram_stories")
        #expect(string(done, "outcome") == "completed")
        #expect(string(done, "card_layout") == "classic")
        #expect(string(done, "card_background") == "flat")
        #expect(string(done, "share_source") == "live_climb_summary")
    }

    @Test
    func storyWithoutInstagramFallsToTheSystemSheetAndReportsWhereItWent() async {
        let rig = Rig()
        rig.exporter.instagramInstalled = false
        await rig.perform(.story)

        #expect(rig.names == ["live_climb_share_action_tap"], "the sheet is still up: nothing has finished")

        rig.exporter.finishSheet(activityType: "com.apple.UIKit.activity.Message", completed: true)

        #expect(rig.names == ["live_climb_share_action_tap", "live_climb_share_activity_done"])
        let done = rig.records[1]
        #expect(string(done, "action") == "story")
        #expect(string(done, "destination") == "messages")
        #expect(flag(done, "completed") == true)
    }

    @Test
    func cancellingTheSystemSheetIsReportedAsCancelledWithNoDestination() async {
        let rig = Rig()
        await rig.perform(.more)
        rig.exporter.finishSheet(activityType: nil, completed: false)

        #expect(rig.names == ["live_climb_share_action_tap", "live_climb_share_activity_done"])
        let done = rig.records[1]
        #expect(string(done, "outcome") == "cancelled")
        #expect(string(done, "destination") == "none")
        #expect(flag(done, "completed") == false)
        #expect(!rig.records.contains { flag($0, "completed") == true }, "a cancel is never a completed share")
    }

    @Test
    func aSystemSheetShareReportsTheActivityTheClimberPicked() async {
        let rig = Rig()
        await rig.perform(.more)
        rig.exporter.finishSheet(activityType: "com.burbn.instagram.shareextension", completed: true)

        let done = rig.records[1]
        #expect(string(done, "action") == "more")
        #expect(string(done, "destination") == "instagram")
        #expect(string(done, "outcome") == "completed")
    }

    @Test
    func aSystemSheetThatCannotBePresentedIsAFailureNotACancel() async {
        let rig = Rig()
        rig.exporter.sheet = .noWindow
        await rig.perform(.more)

        #expect(rig.names == ["live_climb_share_action_tap", "live_climb_share_activity_done"])
        #expect(string(rig.records[1], "outcome") == "failed")
    }

    @Test
    func copyingTheCardReportsACompletionToTheClipboard() async {
        let rig = Rig()
        await rig.perform(.copy)

        #expect(rig.names == ["live_climb_share_action_tap", "live_climb_share_activity_done"])
        #expect(string(rig.records[1], "destination") == "copy")
        #expect(string(rig.records[1], "outcome") == "completed")
    }

    @Test
    func aCopyThatFailsIsReportedAsFailed() async {
        let rig = Rig()
        rig.exporter.copySucceeds = false
        await rig.perform(.copy)

        #expect(string(rig.records[1], "outcome") == "failed")
        #expect(flag(rig.records[1], "completed") == false)
    }

    @Test
    func savingTheCardReportsAPhotosCompletion() async {
        let rig = Rig()
        await rig.perform(.save)

        #expect(string(rig.records[1], "destination") == "save_to_photos")
        #expect(string(rig.records[1], "outcome") == "completed")
    }

    @Test
    func aSaveWithoutPhotosAccessIsReportedAsFailed() async {
        let rig = Rig()
        rig.exporter.saveSucceeds = false
        await rig.perform(.save)

        #expect(string(rig.records[1], "destination") == "save_to_photos")
        #expect(string(rig.records[1], "outcome") == "failed")
    }

    @Test
    func aCardThatDoesNotRenderStillCountsTheTapAndReportsAFailure() async {
        let rig = Rig()
        rig.exporter.rendersCard = false
        await rig.perform(.copy)

        #expect(rig.names == ["live_climb_share_action_tap", "live_climb_share_activity_done"])
        #expect(string(rig.records[1], "outcome") == "failed")
    }

    @Test
    func theCardReportedIsTheOneOnScreenAtTheTap() async {
        let rig = Rig()
        rig.presets.select(layout: .centered)
        await rig.perform(.copy)

        let tap = rig.records.first { $0.name == "live_climb_share_action_tap" }
        #expect(tap.flatMap { string($0, "card_layout") } == "centered")
    }

    // MARK: - Editing the card

    @Test
    func changingTheBackgroundFontAndAccentReportsEachWithItsBoundedValue() {
        let rig = Rig()
        rig.presets.selectBackground(.stairs)
        rig.presets.setFont(.allCases.first { $0 != rig.presets.preferences.font }!)
        rig.presets.setAccent(.allCases.first { $0 != rig.presets.preferences.accent }!)

        #expect(rig.names == ["share_card_edit", "share_card_edit", "share_card_edit"])
        #expect(rig.records.map { string($0, "edit_type") } == ["background", "font", "accent"])
        #expect(string(rig.records[0], "edit_value") == "stairs")
        #expect(string(rig.records[1], "edit_value") == rig.presets.preferences.font.rawValue)
    }

    @Test
    func choosingWhatIsAlreadyChosenIsNotAnEdit() {
        let rig = Rig()
        rig.presets.selectBackground(rig.presets.preferences.background)
        rig.presets.setFont(rig.presets.preferences.font)
        rig.presets.setAccent(rig.presets.preferences.accent)
        rig.presets.reset()

        #expect(rig.names.isEmpty)
    }

    @Test
    func aStatToggleReportsItsDirection() {
        let rig = Rig()
        rig.presets.toggle(.rank)

        #expect(string(rig.records[0], "edit_type") == "stat")
        #expect(string(rig.records[0], "edit_value") == "rank_off")
    }

    @Test
    func aPhotoBackgroundReportsOnlyThatAPhotoWasChosen() {
        let rig = Rig()
        rig.presets.selectPhoto(UIImage())

        #expect(string(rig.records[0], "edit_type") == "photo")
        #expect(string(rig.records[0], "edit_value") == "photo")
    }

    @Test
    func aShareCarriesABucketedCountAndAFlagPerKindEdited() async {
        let rig = Rig()
        rig.presets.selectBackground(.stairs)
        rig.presets.toggle(.rank)
        rig.presets.toggle(.rank)
        await rig.perform(.copy)

        let tap = rig.records.first { $0.name == "live_climb_share_action_tap" }!
        #expect(string(tap, "edit_count_bucket") == "2_5")
        #expect(flag(tap, "edited_background") == true)
        #expect(flag(tap, "edited_stat") == true)
        #expect(flag(tap, "edited_font") == false)
        let done = rig.records.first { $0.name == "live_climb_share_activity_done" }!
        #expect(string(done, "edit_count_bucket") == "2_5")
    }

    @Test
    func aShareWithNoEditsSaysSo() async {
        let rig = Rig()
        await rig.perform(.copy)

        let tap = rig.records[0]
        #expect(string(tap, "edit_count_bucket") == "zero")
        #expect(ShareEditKind.allCases.allSatisfy { flag(tap, "edited_\($0.rawValue)") == false })
    }

    @Test
    func stickerStyleEditsAreReportedAndCountOnTheShare() throws {
        let rig = Rig()
        let container = try ModelContainer(
            for: AscendLocalStore.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let model = StickersViewModel(
            subject: .fixture(),
            modelContext: ModelContext(container),
            userId: nil,
            store: StickerStyleStore(defaults: UserDefaults(suiteName: "ShareSheetAnalyticsTests.\(UUID().uuidString)")!),
            analytics: rig.reporter
        )
        let color = StickerStyle.Color.allCases.first { $0 != model.style.color }!
        model.setColor(color)
        model.setColor(color)

        #expect(rig.names == ["share_card_edit"], "the second, identical choice is not an edit")
        #expect(string(rig.records[0], "edit_type") == "sticker_color")
        #expect(string(rig.records[0], "edit_value") == color.rawValue)
        rig.viewModel.copySticker(UIImage(), content: .sticker(kind: "stack", scope: .climb))
        #expect(flag(rig.records[1], "edited_sticker_color") == true)
    }

    // MARK: - Stickers

    @Test
    func copyingAStickerReportsTheKindAndTheClipboard() {
        let rig = Rig()
        rig.viewModel.copySticker(UIImage(), content: .sticker(kind: "stack", scope: .climb))

        #expect(rig.names == ["live_climb_share_action_tap", "live_climb_share_activity_done"])
        #expect(string(rig.records[0], "sticker_kind") == "stack")
        #expect(string(rig.records[0], "sticker_scope") == "climb")
        #expect(string(rig.records[1], "destination") == "copy")
        #expect(string(rig.records[1], "outcome") == "completed")
    }

    @Test
    func savingAStickerReportsAPhotosCompletion() async {
        let rig = Rig()
        await rig.viewModel.saveSticker(UIImage(), content: .sticker(kind: "weeklyRank", scope: .totals))

        #expect(string(rig.records[0], "action") == "save")
        #expect(string(rig.records[1], "destination") == "save_to_photos")
        #expect(string(rig.records[1], "outcome") == "completed")
    }

    @Test
    func aStickerThatDidNotRenderIsReportedAsFailed() async {
        let rig = Rig()
        rig.viewModel.copySticker(nil, content: .sticker(kind: "stack", scope: .climb))
        await rig.viewModel.saveSticker(nil, content: .sticker(kind: "stack", scope: .climb))

        let outcomes = rig.records.filter { $0.name == "live_climb_share_activity_done" }.map { string($0, "outcome") }
        #expect(outcomes == ["failed", "failed"])
    }

    @Test
    func theStickersViewModelNamesSeasonalAndTotalsStickers() throws {
        let container = try ModelContainer(
            for: AscendLocalStore.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let model = StickersViewModel(
            subject: .fixture(),
            modelContext: ModelContext(container),
            userId: nil,
            store: StickerStyleStore(defaults: UserDefaults(suiteName: "ShareSheetAnalyticsTests.\(UUID().uuidString)")!)
        )

        #expect(model.shareContent(for: .standard(.stack)) == .sticker(kind: "stack", scope: .climb))
        #expect(model.shareContent(for: .seasonal(.turkey)) == .sticker(kind: "seasonal_turkey", scope: .climb))
        model.scope = .totals
        #expect(model.shareContent(for: .standard(.weeklyRank)) == .sticker(kind: "weeklyRank", scope: .totals))
    }
}

/// The composer's open event is fired by the view, so it is proven through the shipped view.
@MainActor
@Suite(.hostsAWindow)
struct ShareSheetComposerOpenTests {
    @Test
    func openingTheComposerReportsItsSourceOnce() async throws {
        let container = try ModelContainer(
            for: AscendLocalStore.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let telemetry = makeTestTelemetry(sink: sink)
        let workout = Workout(duration: 1_800, steps: 3_000, floors: 0, source: .headphoneMotion)
        let view = ShareSheetView(
            source: .loggedClimbResult,
            workout: workout,
            climb: nil,
            climbRank: nil,
            climbRankTotal: nil,
            telemetry: telemetry
        )
        .modelContainer(container)
        .environment(AuthenticationViewModel(observesFirebaseAuth: false))

        try await RenderedScreen.host(view) { screen in
            try await screen.settle()
        }

        let opened = sink.records.filter { $0.name == "share_composer_open" }
        #expect(opened.count == 1)
        #expect(opened.first.flatMap { Self.string($0, "share_source") } == "logged_climb_result")
    }


    private static func string(_ record: EnvelopedTelemetryRecord, _ key: String) -> String? {
        if case .string(let value) = record.parameters[key] { return value }
        return nil
    }
}
