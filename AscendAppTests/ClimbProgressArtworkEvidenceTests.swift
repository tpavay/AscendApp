import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit

@testable import AscendApp

/// Product-level evidence for the photographic climb-progress reveal on the Just Me tab, read
/// off the real, shipping `LiveClimbSessionView` mid-recording at 0, 50 and 100% of the fixture
/// landmarks - both layouts, and both sides of the layout threshold - on whichever simulator runs
/// it (an SE and a 16 Pro). Also the cut-out arriving mid-climb over the photo layout.
///
/// Beyond photographing, every state measures the painted pixels: the lime line has to sit where
/// the manifest's base-to-tip span says it should, the painted landmark has to fill the frame
/// its visible bounds were fitted to, and the colour has to be below the line and not above it.
///
/// Photographed when `ASCEND_EVIDENCE_DIR` is set, and not drawn otherwise.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct ClimbProgressArtworkEvidenceTests {
    /// A catalog climb, read from the bundled `climbs.json` so names, locations and step targets
    /// are the real ones.
    struct Fixture: Sendable, CustomTestStringConvertible {
        let id: String
        var testDescription: String { id }
    }

    /// The three cut-outs kept as test fixtures (`TestFixtures/climb-progress/`): a slender
    /// skyscraper and a lattice tower side by side, and a broad gate stacked. The app bundles
    /// none; the fixture repository stands in for Storage.
    nonisolated static let landmarks: [Fixture] = FixtureClimbProgressImageRepository.fixtureClimbIDs.map(Fixture.init(id:))

    private static let percents = [0, 50, 100]
    /// Where the painted line may sit relative to the manifest's position for it, in points. The
    /// expectation is carried from the painted landmark's measured tip, and the dim grayscale
    /// tip's faintest rows (alpha just over the manifest's 16) fall under the ink threshold, so
    /// the measured tip - and with it the expected line near 100% - reads up to ~1.7pt low.
    private static let markerTolerance: CGFloat = 2

    @Test("The landmark reveals in colour from its base to its tip at every quarter", arguments: landmarks)
    func landmarkRevealsAtEveryQuarter(fixture: Fixture) async throws {
        let size = try Self.deviceScreenSize()
        let climb = try Self.climb(fixture)
        let artwork = try #require(climb.progressArtwork)
        var lines: [Int: Line] = [:]
        var landmark: PaintedLandmark?

        for percent in Self.percents {
            let steps = climb.referenceStepCount * percent / 100
            try await Self.hostSession(climb: climb, steps: steps, size: size) { screen, _ in
                // Each stat cell is one element ("1:00, ELAPSED"), so the readiness check matches
                // the caption inside it. An exact "ELAPSED" never matched, and every read burned
                // the whole 250-read budget - eight minutes of the CI job.
                let texts = try await screen.texts { texts in
                    texts.contains { $0.text.hasSuffix(", ELAPSED") } && texts.contains { $0.text == "End attempt" }
                }
                let text = texts.map(\.text).joined(separator: " ").lowercased()
                #expect(text.contains("climb progress"), "the progress cut-out is on screen: \(text)")
                #expect(text.contains(climb.name.lowercased()), "the climb name is on screen: \(text)")
                #expect(text.contains(climb.city.lowercased()), "the climb location is on screen: \(text)")
                #expect(text.contains("just me") && text.contains("leaderboard"), "the tab toggle is on screen: \(text)")
                #expect(text.contains("of \(climb.referenceStepCount.formatted()) steps"), "steps out of total: \(text)")
                #expect(texts.contains { $0.text.contains("CURRENT") && $0.text.contains("SPM") }, "current pace: \(text)")
                #expect(texts.contains { $0.text.contains("AVG") && $0.text.contains("SPM") }, "average pace: \(text)")
                #expect(!text.contains("heart rate"), "no strap is delivering a reading, so no heart rate: \(text)")

                try screen.photograph(named: "photo-progress-\(fixture.id)-\(String(format: "%03d", percent))pct-\(Int(size.width))pt")

                // The landmark sits below the tab toggle. Side by side, it stands on the left and
                // runs down to the hairline divider above the End attempt bar (12pt above it, 1pt
                // tall); stacked, it spans the full width and ends above the metrics grid, whose
                // first cell is the steps reading.
                let toggle = try #require(texts.first { $0.text == "Leaderboard" }?.frame)
                let endAttempt = try #require(texts.first { $0.text == "End attempt" }?.frame)
                let stepsReading = try #require(texts.first { $0.text.contains("of \(climb.referenceStepCount.formatted()) steps") }?.frame)
                let regionTop = toggle.maxY + 4
                let region: CGRect
                switch artwork.layout {
                case .sideBySide:
                    // Up to the metrics column: at some heights the line shares a row with the
                    // lime percentage beside it, and the two must not read as one run.
                    region = CGRect(x: 0, y: regionTop, width: stepsReading.minX - 2, height: endAttempt.minY - 16 - regionTop)
                case .stacked:
                    region = CGRect(x: 0, y: regionTop, width: screen.bounds.width, height: stepsReading.minY - 4 - regionTop)
                }
                let pixels = try screen.withPixels(scale: Self.pixelScale) { $0 }
                let line = try #require(
                    Self.findLine(in: pixels, region: region),
                    "no lime reveal line painted for \(fixture.id) at \(percent)%"
                )
                lines[percent] = line
                switch artwork.layout {
                case .sideBySide:
                    #expect(stepsReading.minX >= line.maxX, "\(fixture.id): the metrics stand beside the landmark, right of its line \(line.maxX): \(stepsReading.integral)")
                case .stacked:
                    #expect(stepsReading.minY > line.centerY, "\(fixture.id): the metrics sit below the landmark: \(stepsReading.integral)")
                    #expect(abs((line.minX + line.maxX) / 2 - screen.bounds.midX) < 1.5, "\(fixture.id): the stacked landmark is centred across the screen")
                }
                if percent == 50, let line = lines[percent] {
                    landmark = Self.paintedLandmark(in: pixels, line: line, region: region)
                }
            }
        }

        let painted = try #require(landmark, "the landmark was not measured for \(fixture.id)")
        try Self.assertAlignment(fixture: fixture, artwork: artwork, lines: lines, landmark: painted, screenWidth: size.width)
    }

    @Test("Heart rate reads beside the climb name, above the tab toggle, while a strap delivers a reading", arguments: landmarks)
    func heartRateReadsBesideTheClimbName(fixture: Fixture) async throws {
        let size = try Self.deviceScreenSize()
        let climb = try Self.climb(fixture)
        let strap = try await Self.makeConnectedHeartRateMonitor()
        let steps = climb.referenceStepCount / 2

        try await Self.hostSession(
            climb: climb,
            steps: steps,
            size: size,
            heartRate: strap
        ) { screen, viewModel in
            #expect(viewModel.liveHeartRateStatus?.hasCurrentReading == true)
            let texts = try await screen.texts { texts in
                texts.contains { $0.text.localizedCaseInsensitiveContains("beats per minute") }
                    && texts.contains { $0.text == "Leaderboard" }
            }
            let badges = texts.filter { $0.text.localizedCaseInsensitiveContains("beats per minute") }
            #expect(badges.count == 1, "heart rate reads exactly once: \(texts.map(\.text))")
            let toggle = try #require(texts.first { $0.text == "Leaderboard" }?.frame)
            let title = try #require(texts.first { $0.text == climb.name }?.frame)
            if let badge = badges.first?.frame {
                #expect(badge.maxY < toggle.minY, "heart rate sits in the top chrome, above the tab toggle: \(badge.integral)")
                #expect(badge.minX > title.maxX, "heart rate sits to the right of the climb name: \(badge.integral) vs \(title.integral)")
                #expect(badge.maxX <= screen.bounds.maxX - 8, "heart rate stays inside the side gutter: \(badge.integral)")
            }
            try screen.photograph(named: "photo-progress-\(fixture.id)-050pct-heart-rate-\(Int(size.width))pt")
        }
    }

    /// A climb the manifest does not cover keeps the photo-backed Just Me layout it had before:
    /// the hero step count, the summit bar and the stat grid. Every live climb now has a cut-out,
    /// so the control is a coming-soon one.
    @Test("A climb without a cut-out keeps its existing Just Me layout")
    func climbWithoutACutOutIsUnchanged() async throws {
        let size = try Self.deviceScreenSize()
        let climb = try Self.climb(Fixture(id: "the-shard"))
        #expect(climb.progressArtwork == nil)

        // The real hero photo, when the run supplies one, so the photograph shows the shipped look
        // rather than the tier placeholder that paints while a photo loads.
        let heroKey = "climb-images/\(climb.id)/v\(climb.imageSetVersion)/hero.heic"
        if let photoPath = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_HERO_PHOTO"] {
            _ = try DiskAssetCache.climbImages.store(try Data(contentsOf: URL(filePath: photoPath)), for: heroKey)
        }
        defer { try? DiskAssetCache.climbImages.remove(for: heroKey) }

        let steps = climb.referenceStepCount / 2
        try await Self.hostSession(climb: climb, steps: steps, size: size) { screen, _ in
            let text = try await screen.copy { $0.contains("current rank") && $0.contains("average") }
            #expect(!text.contains("climb progress"), "no progress cut-out on a climb the manifest does not cover: \(text)")
            #expect(text.contains("\(climb.referenceStepCount.formatted()) steps"))
            #expect(text.contains("50%") || text.contains("49%"), "the summit bar's percentage still rides its fill: \(text)")
            try await screen.settle(RenderedScreen.Settle.turns(20))
            try screen.photograph(named: "photo-progress-control-\(climb.id)-050pct-\(Int(size.width))pt")
        }
    }

    @Test("Until the cut-out arrives the tab shows its photo layout, then switches mid-climb")
    func cutOutArrivesOverThePhotoLayout() async throws {
        let size = try Self.deviceScreenSize()
        let climb = try Self.climb(Fixture(id: "charminar"))
        let repository = GatedClimbProgressImageRepository()
        let image = try #require(UIImage(contentsOfFile: FixtureClimbProgressImageRepository.fixtureURL(forClimbID: climb.id).path(percentEncoded: false)))

        try await Self.hostSession(
            climb: climb,
            steps: 60,
            size: size,
            progressImages: repository,
            preloadProgressArtwork: false
        ) { screen, viewModel in
            let loading = try await screen.copy { $0.contains("current rank") && $0.contains("average") }
            #expect(!loading.contains("climb progress"), "no cut-out while it loads: \(loading)")
            #expect(loading.contains("60"), "the photo layout carries the live count while the cut-out loads: \(loading)")
            try screen.photograph(named: "photo-progress-\(climb.id)-loading-\(Int(size.width))pt")

            for _ in 0..<100 where !repository.hasPendingRequest {
                try await screen.settle(RenderedScreen.Settle.turns(2))
            }
            #expect(repository.hasPendingRequest, "the session view asked for the cut-out")
            repository.release(with: image)

            let arrived = try await screen.copy { $0.contains("climb progress") }
            #expect(arrived.contains("climb progress"), "the cut-out switched in: \(arrived)")
            #expect(arrived.contains("of \(climb.referenceStepCount.formatted()) steps"))
            #expect(viewModel.isRecording, "the switch did not touch the session")
            #expect(viewModel.totalRecordedSteps == 60)
            try screen.photograph(named: "photo-progress-\(climb.id)-arrived-\(Int(size.width))pt")
        }
    }

    // MARK: - Measurement
    //
    // Everything is read off the painted pixels. The cut-out's accessibility frame cannot stand in
    // for its layout frame: it reports the union of the drawn content, which includes the whole
    // clipped canvas and so reaches well past the column on a heavily padded canvas.

    private static let pixelScale: CGFloat = 3
    private static let lime = RGBA(red: 134, green: 211, blue: 10, alpha: 255)

    /// The reveal line: the run of accent rows that spans most of the column and is at most a
    /// few points tall, and the column's horizontal extent read off it.
    private struct Line {
        let centerY: CGFloat
        let minX: CGFloat
        let maxX: CGFloat
    }

    private struct PaintedLandmark {
        let top: CGFloat
        let bottom: CGFloat
        let minX: CGFloat
        let maxX: CGFloat
        let chromaAbove: Double?
        let chromaBelow: Double?

        var width: CGFloat { maxX - minX }
        var height: CGFloat { bottom - top }
    }

    private static func pixelRange(_ region: CGRect, in pixels: PixelSampler) -> (x: ClosedRange<Int>, y: ClosedRange<Int>) {
        let minX = max(Int((region.minX * pixelScale).rounded(.up)), 0)
        let maxX = min(Int((region.maxX * pixelScale).rounded(.down)) - 1, pixels.width - 1)
        let minY = max(Int((region.minY * pixelScale).rounded(.up)), 0)
        let maxY = min(Int((region.maxY * pixelScale).rounded(.down)) - 1, pixels.height - 1)
        return (minX...maxX, minY...maxY)
    }

    private static func findLine(in pixels: PixelSampler, region: CGRect) -> Line? {
        let range = pixelRange(region, in: pixels)
        let minimumRun = Int(60 * pixelScale)
        var rows: [(y: Int, minX: Int, maxX: Int)] = []
        for y in range.y {
            var count = 0
            var first = Int.max
            var last = Int.min
            for x in range.x where pixels.pixel(x: x, y: y).isClose(to: lime, tolerance: 12) {
                count += 1
                first = min(first, x)
                last = max(last, x)
            }
            if count >= minimumRun { rows.append((y, first, last)) }
        }
        guard let first = rows.first, let last = rows.last, last.y - first.y < Int(4 * pixelScale) else { return nil }
        let center = Double(rows.map(\.y).reduce(0, +)) / Double(rows.count) + 0.5
        return Line(
            centerY: CGFloat(center) / pixelScale,
            minX: CGFloat(rows.map(\.minX).min()!) / pixelScale,
            maxX: CGFloat(rows.map(\.maxX).max()! + 1) / pixelScale
        )
    }

    private static func paintedLandmark(in pixels: PixelSampler, line: Line, region: CGRect) -> PaintedLandmark? {
        let column = CGRect(x: line.minX, y: region.minY, width: line.maxX - line.minX, height: region.height)
        let range = pixelRange(column, in: pixels)
        let lineBand = (line.centerY - 6)...(line.centerY + 6)
        var top = Int.max, bottom = Int.min, left = Int.max, right = Int.min
        for y in range.y where !lineBand.contains(CGFloat(y) / pixelScale) {
            for x in range.x {
                let pixel = pixels.pixel(x: x, y: y)
                guard Int(pixel.red) + Int(pixel.green) + Int(pixel.blue) > 36 else { continue }
                top = min(top, y)
                bottom = max(bottom, y)
                left = min(left, x)
                right = max(right, x)
            }
        }
        guard top <= bottom else { return nil }
        let painted = CGRect(
            x: CGFloat(left) / pixelScale,
            y: CGFloat(top) / pixelScale,
            width: CGFloat(right - left + 1) / pixelScale,
            height: CGFloat(bottom - top + 1) / pixelScale
        )
        let clearance: CGFloat = 8
        let band: CGFloat = 24
        let above = CGRect(x: painted.minX, y: line.centerY - clearance - band, width: painted.width, height: band).intersection(painted)
        let below = CGRect(x: painted.minX, y: line.centerY + clearance, width: painted.width, height: band).intersection(painted)
        return PaintedLandmark(
            top: painted.minY,
            bottom: painted.maxY,
            minX: painted.minX,
            maxX: painted.maxX,
            chromaAbove: meanChroma(pixels, in: above),
            chromaBelow: meanChroma(pixels, in: below)
        )
    }

    /// The mean spread between a pixel's strongest and weakest channel, over the pixels bright
    /// enough to carry colour at all. Zero for a grayscale region.
    private static func meanChroma(_ pixels: PixelSampler, in rect: CGRect) -> Double? {
        guard !rect.isNull, rect.height >= 6 else { return nil }
        let lit = pixels.pixels(in: rect).filter { $0.luminance > 30 }
        guard lit.count > 20 else { return nil }
        let total = lit.reduce(0.0) { sum, pixel in
            let channels = [Int(pixel.red), Int(pixel.green), Int(pixel.blue)]
            return sum + Double(channels.max()! - channels.min()!)
        }
        return total / Double(lit.count)
    }

    private static func assertAlignment(
        fixture: Fixture,
        artwork: ClimbProgressArtwork,
        lines: [Int: Line],
        landmark: PaintedLandmark,
        screenWidth: CGFloat
    ) throws {
        let bounds = artwork.visibleBoundsPixels
        let visibleAspect = Double(bounds.width) / Double(bounds.height)
        let paintedAspect = Double(landmark.width / landmark.height)
        let column = try #require(lines[50])

        // The manifest's base and tip, carried through the painted landmark's own scale.
        let scale = landmark.height / CGFloat(bounds.height)
        let canvasHeight = CGFloat(artwork.canvasHeight)
        let baseY = landmark.top + (artwork.progressBottomY * canvasHeight - CGFloat(bounds.top)) * scale
        let tipY = landmark.top + (artwork.progressTopY * canvasHeight - CGFloat(bounds.top)) * scale

        var report = "PROGRESS-ALIGNMENT \(fixture.id) screen=\(Int(screenWidth))pt "
            + "column x \(Self.format(column.minX))-\(Self.format(column.maxX)) "
            + "painted landmark x \(Self.format(landmark.minX))-\(Self.format(landmark.maxX)) y \(Self.format(landmark.top))-\(Self.format(landmark.bottom)) "
            + "(\(Self.format(landmark.width))x\(Self.format(landmark.height))pt, \(String(format: "%.4f", scale))pt/px) "
            + "aspect painted \(String(format: "%.4f", paintedAspect)) manifest \(String(format: "%.4f", visibleAspect)) "
            + "chroma above/below line at 50%: \(landmark.chromaAbove.map { String(format: "%.1f", $0) } ?? "-")/\(landmark.chromaBelow.map { String(format: "%.1f", $0) } ?? "-") |"

        for percent in Self.percents {
            let line = try #require(lines[percent])
            let expected = baseY - CGFloat(percent) / 100 * (baseY - tipY)
            report += " \(percent)%: line \(Self.format(line.centerY)) expected \(Self.format(expected)) (\(String(format: "%+.2f", line.centerY - expected)))"
            #expect(
                abs(line.centerY - expected) <= Self.markerTolerance,
                "\(fixture.id) at \(percent)%: the line painted at \(line.centerY), the manifest puts it at \(expected)"
            )
            #expect(abs(line.minX - column.minX) < 0.5 && abs(line.maxX - column.maxX) < 0.5, "the line spans the same column at every step")
        }
        print(report)

        #expect(abs(paintedAspect - visibleAspect) / visibleAspect < 0.03, "\(fixture.id) is stretched: painted \(paintedAspect), manifest \(visibleAspect)")
        #expect(landmark.minX >= column.minX - 0.5 && landmark.maxX <= column.maxX + 0.5, "\(fixture.id) paints outside its column")
        #expect(abs((landmark.minX + landmark.maxX) / 2 - (column.minX + column.maxX) / 2) < 1.5, "\(fixture.id) is not centred in its column")
        // The dim layer is true grayscale, so colour above the line would be a mask that has
        // drifted off the line.
        let chromaAbove = try #require(landmark.chromaAbove)
        let chromaBelow = try #require(landmark.chromaBelow)
        #expect(chromaAbove < 3, "\(fixture.id) at 50%: colour shows above the line (chroma \(chromaAbove))")
        #expect(chromaBelow > 12, "\(fixture.id) at 50%: the band below the line is not in colour (chroma \(chromaBelow))")
    }

    private static func format(_ value: CGFloat) -> String {
        String(format: "%.2f", value)
    }

    // MARK: - Hosting

    private static func hostSession(
        climb: Climb,
        steps: Int,
        size: CGSize,
        progressImages: any ClimbProgressImageRepository = FixtureClimbProgressImageRepository(),
        preloadProgressArtwork: Bool = true,
        heartRate strap: (monitor: HeartRateMonitorService, recorder: LiveHeartRateRecorder, client: FakeBluetoothHeartRateClient)? = nil,
        _ body: @MainActor (HostedScreen, LiveClimbSessionViewModel) async throws -> Void
    ) async throws {
        let container = try RetainedModelContainer.inMemory(
            for: Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self,
            ClimbAttempt.self, BestEffortCacheEntry.self, BestEffortCacheMetadata.self
        )
        let motionSession = FakeHeadphoneMotionSession()
        let viewModel = LiveClimbSessionViewModel(
            climb: climb,
            motionSession: motionSession,
            climbService: ClimbService(
                catalogRepository: StubClimbCatalogRepository(climbs: [climb])
            ),
            leaderboardService: StubLiveReplayLeaderboardService(),
            heartRateRecorder: strap?.recorder ?? LiveHeartRateRecorder(),
            heartRateMonitor: strap?.monitor ?? HeartRateMonitorService(userDefaults: Self.freshDefaults()),
            progressImageRepository: progressImages
        )

        viewModel.start(modelContext: container.mainContext)
        if preloadProgressArtwork {
            await viewModel.loadProgressArtworkIfNeeded()
        }
        motionSession.stepCount = steps
        // A plausible 80 steps per minute, with at least a minute on the clock.
        motionSession.duration = max(Double(steps) * 0.75, 60)
        #expect(viewModel.isRecording)

        if let strap {
            let deviceID = try #require(strap.monitor.rememberedDevice?.id)
            strap.client.emit(.connected(id: deviceID, name: "Test Strap"))
            await Task.yield()
            strap.client.emit(.measurement(
                HeartRateMeasurement(beatsPerMinute: 142, sensorContact: .detected, receivedAt: Date())
            ))
            await Task.yield()
        }

        try await RenderedScreen.host(
            LiveClimbSessionView(viewModel: viewModel)
                .environment(ModerationStore.shared)
                .modelContainer(container),
            size: size
        ) { screen in
            try await body(screen, viewModel)
        }
    }

    /// The simulator's own screen, so the SE run lays out at the SE's size and safe area and the
    /// 16 Pro run at its own.
    private static func deviceScreenSize() throws -> CGSize {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        return scene.screen.bounds.size
    }

    private static func climb(_ fixture: Fixture) throws -> Climb {
        try #require(
            BundledClimbCatalog.climbs.first { $0.id == fixture.id },
            "\(fixture.id) is not in the bundled climbs.json"
        )
    }

    private static func makeConnectedHeartRateMonitor() async throws -> (
        monitor: HeartRateMonitorService,
        recorder: LiveHeartRateRecorder,
        client: FakeBluetoothHeartRateClient
    ) {
        let defaults = Self.freshDefaults()
        defaults.set(UUID().uuidString, forKey: "heartRateMonitor.rememberedDeviceID")
        defaults.set("Test Strap", forKey: "heartRateMonitor.rememberedDeviceName")

        let client = FakeBluetoothHeartRateClient()
        let monitor = HeartRateMonitorService(
            userDefaults: defaults,
            authorizationProvider: { .allowedAlways },
            clientFactory: { eventHandler in
                client.onEvent = eventHandler
                return client
            },
            connectionSleep: { duration in try await Task.sleep(for: duration) }
        )
        return (monitor, LiveHeartRateRecorder(sources: [monitor]), client)
    }

    private static func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "ClimbProgressArtworkEvidenceTests.\(UUID().uuidString)")!
    }
}
