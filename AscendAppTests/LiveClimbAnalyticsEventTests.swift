import Testing
@testable import AscendApp

struct LiveClimbAnalyticsEventTests {
    @Test
    func homeDailyTapUsesStableClimbParameters() {
        let record = LiveClimbAnalyticsEvent
            .homeDailyTapped(
                climb: .preview,
                homeState: .neverClimbed(totalClimbs: 100)
            )
            .record

        #expect(record.name == "live_climb_home_daily_tap")
        #expect(record.destinations == [.analytics])
        #expect(record.parameters["climb_id"] == .string("empire-state-building"))
        #expect(record.parameters["climb_tier"] == .string("gold"))
        #expect(record.parameters["climb_category"] == .string("skyscraper"))
        #expect(record.parameters["climb_steps_bucket"] == .string("100_plus"))
        #expect(record.parameters["home_state"] == .string("never_climbed"))
    }

    @Test
    func completedAttemptRecordsCompletionEventWithBuckets() {
        let record = LiveClimbAnalyticsEvent
            .attemptCompleted(
                climb: .preview,
                entryPoint: .homeDaily,
                durationSeconds: 451,
                steps: 809,
                rank: 12,
                rankTotal: 91
            )
            .record

        #expect(record.name == "live_climb_attempt_completed")
        #expect(record.parameters["entry_point"] == .string("home_daily"))
        #expect(record.parameters["duration_bucket"] == .string("5_10_min"))
        #expect(record.parameters["steps_bucket"] == .string("100_plus"))
        #expect(record.parameters["rank_bucket"] == .string("top_25"))
        #expect(record.parameters["rank_total_bucket"] == .string("51_100"))
    }

    @Test
    func summaryShareTapKeepsRankBucketed() {
        let record = LiveClimbAnalyticsEvent
            .summaryShareTapped(
                climb: .preview,
                rank: 1,
                rankTotal: 2_500
            )
            .record

        #expect(record.name == "live_climb_summary_share_tap")
        #expect(record.parameters["rank_bucket"] == .string("first"))
        #expect(record.parameters["rank_total_bucket"] == .string("100_plus"))
    }

    @Test
    func headphoneHelpOpenIncludesClimbSurfaceAndEntryPoint() {
        let record = LiveClimbAnalyticsEvent
            .headphoneHelpOpened(
                climb: .preview,
                entryPoint: .homeDaily,
                surface: .detailHelpButton
            )
            .record

        #expect(record.name == "live_climb_headphone_help_open")
        #expect(record.destinations == [.analytics])
        #expect(record.parameters["climb_id"] == .string("empire-state-building"))
        #expect(record.parameters["entry_point"] == .string("home_daily"))
        #expect(record.parameters["surface"] == .string("detail_help_button"))
    }

    @Test
    func headphoneHelpOpenWithoutClimbOmitsClimbParameters() {
        let record = LiveClimbAnalyticsEvent
            .headphoneHelpOpened(
                climb: nil,
                entryPoint: .unknown,
                surface: .sessionGate
            )
            .record

        #expect(record.name == "live_climb_headphone_help_open")
        #expect(record.parameters["climb_id"] == nil)
        #expect(record.parameters["surface"] == .string("session_gate"))
    }

    @Test
    func browseHelpOpenRecordsAnalyticsEvent() {
        let record = LiveClimbAnalyticsEvent.browseHelpOpened.record

        #expect(record.name == "live_climb_browse_help_open")
        #expect(record.destinations == [.analytics])
        #expect(record.parameters.isEmpty)
    }

    @Test
    func shareActionTapIncludesSurfaceAndCardType() {
        let record = LiveClimbAnalyticsEvent
            .shareActionTapped(
                climb: .preview,
                surface: .systemSheet,
                cardType: .liveClimb
            )
            .record

        #expect(record.name == "live_climb_share_action_tap")
        #expect(record.parameters["share_surface"] == .string("system_sheet"))
        #expect(record.parameters["card_type"] == .string("live_climb"))
    }
}
