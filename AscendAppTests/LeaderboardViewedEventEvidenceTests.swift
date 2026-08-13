import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Evidence for the launch measurement gap the board was shipped to close: an
/// opened leaderboard now reports the visit.
///
/// Each case takes one entry into the board, derives that visit's context from a real
/// `LeaderboardViewModel`, ships the event through a real `TelemetryManager` carrying
/// both an analytics sink and a crashlytics-only sink, and renders the exact payload
/// analytics receives. The crashlytics sink is what proves destination filtering: a
/// view event that reached it would be a payload nobody asked for.
///
/// This suite hosts no window. The board's own pixels are already photographed by
/// `LeaderboardWindowLabelEvidenceTests`, which renders this same route; what no
/// screenshot can show is the payload the visit ships, and that needs no window.
///
/// Files land in `ASCEND_EVIDENCE_DIR` when it is set and in the test host's temporary
/// directory otherwise; the path is logged either way. Nothing reads them back - these
/// are evidence, not golden-image assertions.
@MainActor
struct LeaderboardViewedEventEvidenceTests {
    /// The default board: tab entry, weekly window, no demographic filters.
    @Test
    func theTabVisitReportsItsSourceAndAnUnfilteredBoard() throws {
        let router = TabRouter()
        router.select(.leaderboard, reason: .tabBarTap)
        let source = LeaderboardAnalyticsEvent.ViewSource(tabSelection: router.selectionReason)
        #expect(source == .tab)

        let payload = try emit(context: boardContext(timeFrame: .weekly), source: source)

        #expect(payload.record.name == "leaderboard_viewed")
        #expect(payload.eventParameters == [
            "source": .string("tab"),
            "metric": .string("climb"),
            "time_frame": .string("weekly"),
            "has_active_filters": .bool(false)
        ])
        #expect(payload.record.destinations == [.analytics])
        #expect(payload.crashlyticsRecordCount == 0)

        try capture(
            rows: [(
                label: "Leaderboard tab -> the WEEKLY board, no demographic filters",
                payload: payload
            )],
            named: "leaderboard-viewed-tab-unfiltered"
        )
    }

    /// The other entry into the same tab, reported apart from it, with and without a
    /// climber narrowing the field.
    @Test
    func theHomeRankCardVisitReportsItsOwnSourceAndAnyActiveFilters() throws {
        let router = TabRouter()
        router.select(.leaderboard, reason: .homeRankCard)
        let source = LeaderboardAnalyticsEvent.ViewSource(tabSelection: router.selectionReason)
        #expect(source == .homeRankCard)

        let payload = try emit(context: boardContext(timeFrame: .monthly), source: source)

        #expect(payload.eventParameters == [
            "source": .string("home_rank_card"),
            "metric": .string("climb"),
            "time_frame": .string("monthly"),
            "has_active_filters": .bool(false)
        ])
        #expect(payload.record.destinations == [.analytics])
        #expect(payload.crashlyticsRecordCount == 0)

        // Identity stays the Firebase UID the manager already carries: the event
        // itself names no climber.
        #expect(payload.analyticsUserIDs == [Self.firebaseUID])
        #expect(payload.eventParameters.keys.contains { $0.contains("user") } == false)

        let filtered = try emit(
            context: boardContext(
                timeFrame: .monthly,
                ageGroup: .age30To34,
                bodyWeightFilter: .pounds200Plus,
                locationFilter: .currentCountry
            ),
            source: source
        )

        #expect(filtered.eventParameters["has_active_filters"] == .bool(true))
        #expect(filtered.eventParameters["source"] == .string("home_rank_card"))
        #expect(filtered.eventParameters["time_frame"] == .string("monthly"))
        #expect(filtered.record.destinations == [.analytics])
        #expect(filtered.crashlyticsRecordCount == 0)

        try capture(
            rows: [
                (label: "Home rank card -> the MONTHLY board", payload: payload),
                (
                    label: "same visit, AGE 30-34 + 200+ LB + COUNTRY applied",
                    payload: filtered
                )
            ],
            named: "leaderboard-viewed-rank-card"
        )
    }

    // MARK: - Emission

    private static let firebaseUID = "0kZ1qA7fireBaseUid"

    private struct Payload {
        let record: EnvelopedTelemetryRecord
        let crashlyticsRecordCount: Int
        let analyticsUserIDs: [String?]

        /// The event's own contract, without the envelope every record carries.
        var eventParameters: [String: TelemetryValue] {
            record.parameters.filter { TelemetryEnvelope.propertyKeys.contains($0.key) == false }
        }

        var envelopeParameters: [String: TelemetryValue] {
            record.parameters.filter { TelemetryEnvelope.propertyKeys.contains($0.key) }
        }
    }

    private func emit(
        context: LeaderboardAnalyticsContext,
        source: LeaderboardAnalyticsEvent.ViewSource
    ) throws -> Payload {
        let analytics = InMemoryTelemetrySink(destination: .analytics)
        let crashlytics = InMemoryTelemetrySink(destination: .crashlytics)
        let telemetry = makeTestTelemetry(sinks: [analytics, crashlytics])

        telemetry.setUserId(Self.firebaseUID)
        telemetry.track(LeaderboardAnalyticsEvent.viewed(context: context, source: source))

        let record = try #require(
            analytics.records.first { $0.name == "leaderboard_viewed" },
            "the analytics destination received no leaderboard_viewed"
        )

        return Payload(
            record: record,
            crashlyticsRecordCount: crashlytics.records.count,
            analyticsUserIDs: analytics.userIDs
        )
    }

    /// The context comes off a real `LeaderboardViewModel`, which is the property the
    /// route hands the event - a hand-built context would prove nothing about it.
    private func boardContext(
        timeFrame: LeaderboardTimeFrame,
        ageGroup: LeaderboardAgeGroup? = nil,
        bodyWeightFilter: LeaderboardBodyWeightFilter = .all,
        locationFilter: LeaderboardLocationFilter = .all
    ) -> LeaderboardAnalyticsContext {
        let viewModel = LeaderboardViewModel()
        viewModel.selectedTimeFrame = timeFrame
        viewModel.selectedAgeGroup = ageGroup
        viewModel.selectedBodyWeightFilter = bodyWeightFilter
        viewModel.selectedLocationFilter = locationFilter
        return viewModel.analyticsContext
    }

    // MARK: - Rendering

    private typealias Row = (label: String, payload: Payload)

    private func capture(rows: [Row], named name: String) throws {
        let renderer = ImageRenderer(content: evidenceSheet(rows: rows))
        renderer.scale = 3
        let image = try #require(renderer.uiImage, "ImageRenderer produced no image")
        let png = try #require(image.pngData(), "UIImage produced no PNG data")

        let url = Self.evidenceDirectory.appending(path: "\(name).png")
        try png.write(to: url)
        #expect(png.count > 5_000)

        let transcript = rows
            .map { Self.transcriptRow(label: $0.label, payload: $0.payload) }
            .joined(separator: "\n\n")
        let transcriptURL = Self.evidenceDirectory.appending(path: "\(name).txt")
        try Data(transcript.utf8).write(to: transcriptURL)

        print(transcript)
        print("Rendered leaderboard_viewed evidence: \(url.path())")
        print("Wrote leaderboard_viewed transcript: \(transcriptURL.path())")
    }

    private static var evidenceDirectory: URL {
        URL(
            filePath: ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
                ?? NSTemporaryDirectory()
        )
    }

    private func evidenceSheet(rows: [Row]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("LEADERBOARD_VIEWED - WHAT ANALYTICS RECEIVES")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                payloadPanel(label: row.label, payload: row.payload)
            }

            if let envelope = rows.first?.payload.envelopeParameters {
                Text("envelope: \(Self.sortedLines(envelope).joined(separator: "  "))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
            }

            Text("identity: \(Self.firebaseUID) (Firebase UID, set on the manager - not an event property)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(18)
        .frame(width: 520, alignment: .leading)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
    }

    private func payloadPanel(label: String, payload: Payload) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(red: 0.525, green: 0.827, blue: 0.039))

            Text("leaderboard_viewed -> \(Self.destinationList(payload.record.destinations))")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)

            ForEach(Self.sortedLines(payload.eventParameters), id: \.self) { line in
                Text(line)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white)
            }

            Text("crashlytics sink records: \(payload.crashlyticsRecordCount)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private static func sortedLines(_ parameters: [String: TelemetryValue]) -> [String] {
        parameters
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.stringValue)" }
    }

    private static func destinationList(_ destinations: Set<TelemetryDestination>) -> String {
        destinations.map(\.displayName).sorted().joined(separator: ", ")
    }

    private static func transcriptRow(label: String, payload: Payload) -> String {
        """
        \(label)
          event         leaderboard_viewed
          destinations  \(destinationList(payload.record.destinations))
          properties    \(sortedLines(payload.eventParameters).joined(separator: " "))
          envelope      \(sortedLines(payload.envelopeParameters).joined(separator: " "))
          identity      \(payload.analyticsUserIDs.compactMap { $0 }.joined(separator: ",")) (Firebase UID)
          crashlytics   \(payload.crashlyticsRecordCount) records
        """
    }
}
