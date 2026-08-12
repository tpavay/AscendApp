import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import AscendApp

/// The rules a pre-formatted stat cluster has to keep: it is offered only when
/// its data resolves, it behaves as one sticker, it starts plate-free, and it
/// never spells the brand.
@MainActor
struct ShareStatClusterPresetTests {

    // MARK: - Availability follows the data

    /// A climb that recorded no heart rate is offered every other cluster and
    /// none of the heart-rate ones — the same rule the summary screen keeps:
    /// show the data or do not.
    @Test
    func heartRateClustersAreWithheldFromAWorkoutWithoutHeartRate() {
        let withHeartRate = Set(Self.liveClimbViewModel().availablePresets().map(\.id))
        let without = Set(Self.liveClimbViewModel(heartRate: false).availablePresets().map(\.id))

        let heartRateClusters: Set<String> = ["hr-hero", "hr-row", "full-grid", "hr-minimal"]
        #expect(heartRateClusters.isSubset(of: withHeartRate))
        #expect(without.intersection(heartRateClusters).isEmpty)
        // Everything that does not read heart rate survives its absence.
        #expect(withHeartRate.subtracting(heartRateClusters) == without)
        #expect(!without.isEmpty)
    }

    /// The same catalog serves all three session types, and each one is offered
    /// exactly the clusters its data supports.
    @Test
    func aLiveClimbARoutineAndAJustClimbAreEachOfferedTheClustersTheirDataSupports() {
        let liveClimb = Set(Self.liveClimbViewModel().availablePresets().map(\.id))
        let routine = Set(Self.routineViewModel().availablePresets().map(\.id))
        let justClimb = Set(Self.justClimbViewModel().availablePresets().map(\.id))

        // A ranked climb has the tower, the field and the heart rate, so it gets
        // everything except the cluster built around a routine's intervals.
        #expect(liveClimb == Set(ShareStatClusterPresets.all.map(\.id)).subtracting(["routine"]))

        // A routine has no tower and no field, so nothing built on either is
        // offered — but it does have its own cluster.
        #expect(routine.contains("routine"))
        #expect(routine.contains("row"))
        #expect(routine.isDisjoint(with: ["hero", "rank", "receipt", "full-grid"]))

        // A Just Climb is neither, and still gets the arrangements that need
        // only what every session records.
        #expect(justClimb.contains("row"))
        #expect(justClimb.contains("minimal"))
        #expect(justClimb.contains("splits"))
        #expect(justClimb.isDisjoint(with: ["hero", "rank", "receipt", "routine", "full-grid"]))
    }

    /// A session that never recorded how many intervals it ran is not offered the
    /// cluster built around that number.
    ///
    /// The count is frozen into the workout at save time, so a routine the
    /// climber has since edited cannot rewrite a card, and a session from before
    /// the count was recorded simply loses a stat it never truthfully had rather
    /// than being handed today's answer.
    @Test
    func aRoutineSessionThatNeverRecordedItsIntervalCountIsNotOfferedTheRoutineCluster() {
        let recorded = Self.routineViewModel()
        let unrecorded = Self.routineViewModel(intervalCount: nil)

        #expect(recorded.resolved(ShareStatRef(kind: .routineIntervals))?.value == "8")
        #expect(recorded.availablePresets().map(\.id).contains("routine"))

        #expect(unrecorded.resolved(ShareStatRef(kind: .routineIntervals)) == nil)
        #expect(!unrecorded.availablePresets().map(\.id).contains("routine"))
        // Everything that does not read the interval count survives its absence.
        #expect(unrecorded.availablePresets().map(\.id).contains("row"))
    }

    /// A session too short to divide into five step ranges is not offered the
    /// Splits cluster.
    ///
    /// The trap the gate has to survive: `.splits` resolves off the pace
    /// timeline, which a two-second session still has, while the step-range
    /// table the cluster actually draws is built from a different array that
    /// comes back empty. Gated on the stat, the picker offered a heading, a rule
    /// and a gap where five rows belong.
    @Test
    func aSessionTooShortForStepRangesIsNotOfferedTheSplitsCluster() {
        let viewModel = ShareComposerViewModel(
            workout: Self.recordedWorkout(
                name: "Just Climb",
                trackingMode: .justClimb,
                heartRate: false,
                recordedSteps: 4
            ),
            measurementSystem: .imperial,
            stepHeight: MeasurementSystem.imperial.defaultStepHeight
        )

        let splits = viewModel.splits()
        #expect(viewModel.resolved(ShareStatRef(kind: .splits)) != nil, "the old gate would not have fired")
        #expect(splits?.rows.isEmpty == false)
        #expect(splits?.stepQuintileRows.isEmpty == true)
        #expect(!viewModel.availablePresets().map(\.id).contains("splits"))
    }

    /// Every cluster on offer actually draws: the tree resolves against the
    /// session's data rather than being placed as an empty frame.
    @Test
    func everyOfferedClusterDrawsSomething() {
        for viewModel in [Self.liveClimbViewModel(), Self.routineViewModel(), Self.justClimbViewModel()] {
            for preset in viewModel.availablePresets() {
                #expect(!viewModel.presetPreview(for: preset).isEmpty, "\(preset.id) drew nothing")
            }
        }
    }

    // MARK: - One movable unit

    /// Placing a cluster adds exactly one sticker, and moving, resizing and
    /// deleting it are the ordinary sticker operations — there is no second
    /// system underneath.
    @Test
    func aClusterIsOneStickerThatDragsResizesAndDeletes() throws {
        let viewModel = Self.liveClimbViewModel()
        let hero = try #require(viewModel.availablePresets().first { $0.id == "hero" })

        viewModel.addPresetSticker(hero)
        #expect(viewModel.stickers.count == 1)

        var placed = try #require(viewModel.stickers.first)
        #expect(viewModel.selectedID == placed.id)
        #expect(placed.isPreset)

        placed.position = CGPoint(x: 0.3, y: 0.7)
        placed.scale = 1.6
        viewModel.update(placed)
        let moved = try #require(viewModel.stickers.first)
        #expect(moved.position == CGPoint(x: 0.3, y: 0.7))
        #expect(moved.scale == 1.6)
        #expect(viewModel.stickers.count == 1, "a cluster must move as one unit, not as several")

        viewModel.deleteSticker(moved.id)
        #expect(viewModel.stickers.isEmpty)
        #expect(viewModel.selectedID == nil)
    }

    /// Releasing a cluster over the trash deletes it, exactly like any sticker.
    @Test
    func aClusterReleasedOverTheTrashIsDeleted() throws {
        let viewModel = Self.liveClimbViewModel()
        let first = try #require(viewModel.availablePresets().first)
        viewModel.addPresetSticker(first)
        let id = try #require(viewModel.stickers.first?.id)

        let canvas = CGSize(width: 390, height: 845)
        let trash = viewModel.trashRect(in: canvas)
        #expect(viewModel.handleDragEnded(id: id, center: CGPoint(x: trash.midX, y: trash.midY), canvasSize: canvas))
        #expect(viewModel.stickers.isEmpty)
    }

    /// A cluster's metrics are the curated set. Toggling one off would leave the
    /// arrangement drawing stats it was not designed around.
    @Test
    func aClusterKeepsItsCuratedMetrics() throws {
        let viewModel = Self.liveClimbViewModel()
        let hero = try #require(viewModel.availablePresets().first { $0.id == "hero" })
        viewModel.addPresetSticker(hero)
        let id = try #require(viewModel.stickers.first?.id)

        viewModel.toggleStat(ShareStatRef(kind: .calories), for: id)
        let placed = try #require(viewModel.stickers.first)
        #expect(placed.statRefs == hero.stats)
    }

    // MARK: - Plate-free by default

    /// A cluster arrives with no backing panel and no plate in its tree; the
    /// existing text-background control is still what adds one.
    @Test
    func aClusterStartsPlateFreeAndTheExistingControlStillAddsAPlate() throws {
        let viewModel = Self.liveClimbViewModel()
        for preset in viewModel.availablePresets() {
            #expect(
                viewModel.presetPreview(for: preset).node.modifiers.background == nil,
                "\(preset.id) shipped with a plate"
            )
        }

        let hero = try #require(viewModel.availablePresets().first { $0.id == "hero" })
        viewModel.addPresetSticker(hero)
        let bare = try #require(viewModel.stickers.first)
        #expect(bare.textBackground == .none)
        #expect(viewModel.content(for: bare).node.modifiers.background == nil)

        viewModel.cycleTextBackground(for: bare.id)
        let plated = try #require(viewModel.stickers.first)
        #expect(plated.textBackground == .dark)
        #expect(viewModel.content(for: plated).node.modifiers.background != nil)
        #expect(viewModel.content(for: plated).node.modifiers.padding != nil)
    }

    /// A cluster starts in the face it was designed in, and the rail's font
    /// control still moves it to any of the six.
    @Test
    func aClusterStartsInItsDesignedFaceAndTheRailCanStillChangeIt() throws {
        let viewModel = Self.liveClimbViewModel()
        let receipt = try #require(viewModel.availablePresets().first { $0.id == "receipt" })
        #expect(receipt.font == .spaceMono)

        viewModel.addPresetSticker(receipt)
        let placed = try #require(viewModel.stickers.first)
        #expect(placed.font == .spaceMono)

        viewModel.setFont(.playfair, for: placed.id)
        let restyled = try #require(viewModel.stickers.first)
        #expect(viewModel.content(for: restyled).context.font == .playfair)
    }

    /// Only the three faces the review settled on are used as defaults.
    @Test
    func clustersAreDesignedInAntonMontserratOrSpaceMono() {
        let allowed: Set<ShareStickerFont> = [.anton, .montserrat, .spaceMono]
        for preset in ShareStatClusterPresets.all {
            #expect(allowed.contains(preset.font), "\(preset.id) is designed in an unapproved face")
        }
    }

    // MARK: - Legibility over a photograph

    /// A cluster is bare text on somebody's photograph, so no run of it may ship
    /// untreated — and the small tracked-out caps, which a drop shadow alone
    /// leaves washed out against snow or a blown sky, take the outline as well.
    ///
    /// The plate is not the answer here: it is the climber's one-tap choice, and
    /// the default has to hold up without it.
    @Test
    func everyRunOfClusterTextCarriesALegibilityTreatment() {
        // The catalog's own threshold, read rather than restated: three numbers
        // for one rule is how the next change picks the wrong one.
        let smallText = ShareStatClusterPresets.outlineBelow

        for preset in ShareStatClusterPresets.all {
            var styles: [(run: String, style: ShareCardTextStyle)] = []
            var splitTables = 0

            for element in Self.elements(of: preset.content) {
                switch element {
                case .text(let text):
                    styles.append(("text", text.style))
                case .metric(let metric):
                    styles.append(("value", metric.value))
                    styles.append(("label", metric.label))
                case .splits(let spec):
                    splitTables += 1
                    #expect(
                        spec.legibility == .outline,
                        "\(preset.id) left the split table's row text untreated"
                    )
                default:
                    break
                }
            }

            #expect(!styles.isEmpty, "\(preset.id) drew no text at all")
            for entry in styles {
                #expect(
                    entry.style.legibility != .none,
                    "\(preset.id) ships a bare \(entry.run) at \(entry.style.size)"
                )
                if entry.style.size < smallText {
                    #expect(
                        entry.style.legibility == .outline,
                        "\(preset.id)'s \(entry.run) at \(entry.style.size) is small enough to need the outline"
                    )
                }
            }
            if preset.id == "splits" { #expect(splitTables == 1) }
        }
    }

    /// The treatment belongs to the run, not to the plate: adding a panel is the
    /// climber's choice and must not be the thing that makes text readable.
    @Test
    func addingAPanelDoesNotChangeTheTextTreatment() throws {
        let viewModel = Self.liveClimbViewModel()
        let hero = try #require(viewModel.availablePresets().first { $0.id == "hero" })
        viewModel.addPresetSticker(hero)
        let placed = try #require(viewModel.stickers.first)

        let bare = Self.legibilities(of: viewModel.content(for: placed).node)
        viewModel.cycleTextBackground(for: placed.id)
        let plated = try #require(viewModel.stickers.first)
        #expect(Self.legibilities(of: viewModel.content(for: plated).node) == bare)
        #expect(!bare.contains(.none))
    }

    /// A card drawn on its own solid panel takes no treatment: the shipped recap
    /// templates must be untouched by this.
    @Test
    func bundledRecapTemplatesTakeNoLegibilityTreatment() throws {
        let templates = ShareCardTemplateStore(bundle: .main).templates(for: [.climb, .standing])
        #expect(!templates.isEmpty)
        for template in templates {
            #expect(
                Self.legibilities(of: template.root).allSatisfy { $0 == .none },
                "\(template.id) picked up a treatment meant for bare text"
            )
        }
    }

    private static func legibilities(of node: ShareCardNode) -> [ShareCardTextLegibility] {
        elements(of: node).flatMap { element -> [ShareCardTextLegibility] in
            switch element {
            case .text(let text): return [text.style.legibility]
            case .metric(let metric): return [metric.value.legibility, metric.label.legibility]
            default: return []
            }
        }
    }

    // MARK: - Branding

    /// The canvas lockup is the only place the brand appears. A cluster that
    /// drew a wordmark element, or spelled the name in copy, would put it on the
    /// export twice.
    @Test
    func noClusterSpellsOrDrawsTheWordmark() {
        for preset in ShareStatClusterPresets.all {
            for element in Self.elements(of: preset.content) {
                if case .wordmark = element {
                    Issue.record("\(preset.id) drew the wordmark inside the cluster")
                }
                guard case .text(let text) = element else { continue }
                for segment in text.segments + (text.fallback ?? []) {
                    guard let literal = segment.literal?.uppercased() else { continue }
                    #expect(
                        !literal.contains("ASCEND") && !literal.contains("SCEND"),
                        "\(preset.id) spelled the wordmark as text"
                    )
                }
            }
        }
    }

    // MARK: - Heart-rate copy

    /// One place owns the copy, so every heart-rate sticker and every cluster
    /// reads the same: no BPM suffix, no glyph.
    @Test
    func heartRateStatsReadAverageHrAndMaxHr() throws {
        let viewModel = Self.liveClimbViewModel()

        let average = try #require(viewModel.resolved(ShareStatRef(kind: .avgHeartRate)))
        let maximum = try #require(viewModel.resolved(ShareStatRef(kind: .maxHeartRate)))
        #expect(average.label == "AVERAGE HR")
        #expect(maximum.label == "MAX HR")
        for stat in [average, maximum] {
            let rendered = "\(stat.label) \(stat.value)"
            let mentionsBpm = rendered.range(of: "BPM", options: .caseInsensitive) != nil
            let isPlainText = rendered.allSatisfy(\.isASCII)
            #expect(!mentionsBpm, "\(stat.kind) still carries a BPM suffix")
            #expect(isPlainText, "a glyph crept into the heart-rate copy")
        }
    }

    /// The max sits beneath the average on the heart-rate clusters, never beside
    /// it in a row of its own.
    @Test
    func theHeartRateHeroPutsMaxBeneathAverage() throws {
        let hero = try #require(ShareStatClusterPresets.preset(id: "hr-hero"))
        let stack = try #require(Self.verticalStack(of: hero.content))
        let averageIndex = try #require(Self.index(ofMetric: .avgHeartRate, in: stack))
        let maximumIndex = try #require(Self.index(ofMetric: .maxHeartRate, in: stack))
        #expect(maximumIndex == averageIndex + 1)

        let maximum = try #require(Self.metric(.maxHeartRate, in: stack))
        #expect(maximum.labelPlacement == .leading, "the max reads as MAX HR 176 on one line")
        #expect(maximum.labelPolicy == .automatic)
    }

    // MARK: - Recap backgrounds

    /// A recap only skips the automatic stats sheet. The plus button still
    /// works, so a cluster lands on one exactly as on any other background — and
    /// the recap's own burned-in lockup stays the only wordmark.
    @Test
    func aClusterCanBePlacedOnARecapBackground() throws {
        let viewModel = Self.liveClimbViewModel()
        viewModel.resetForNewBackground(.recap(Self.solidImage()))
        #expect(!viewModel.shouldRenderCanvasWordmark)

        let row = try #require(viewModel.availablePresets().first { $0.id == "row" })
        viewModel.addPresetSticker(row)
        let placed = try #require(viewModel.stickers.first)
        #expect(placed.isPreset)
        #expect(!viewModel.content(for: placed).isEmpty)
    }

    // MARK: - Tree readers

    private static func elements(of node: ShareCardNode) -> [ShareCardElement] {
        guard case .stack(let stack) = node.element else { return [node.element] }
        return [node.element] + stack.children.flatMap(elements(of:))
    }

    private static func verticalStack(of node: ShareCardNode) -> ShareCardStack? {
        guard case .stack(let stack) = node.element, stack.axis == .vertical else { return nil }
        return stack
    }

    private static func index(ofMetric kind: ShareStatStickerKind, in stack: ShareCardStack) -> Int? {
        stack.children.firstIndex { child in
            guard case .metric(let metric) = child.element else { return false }
            return metric.stat?.kind == kind
        }
    }

    private static func metric(_ kind: ShareStatStickerKind, in stack: ShareCardStack) -> ShareCardMetric? {
        for child in stack.children {
            guard case .metric(let metric) = child.element, metric.stat?.kind == kind else { continue }
            return metric
        }
        return nil
    }

    // MARK: - Fixtures

    private static func liveClimbViewModel(heartRate: Bool = true) -> ShareComposerViewModel {
        ShareComposerViewModel(
            workout: recordedWorkout(
                name: "Live Climb",
                trackingMode: .liveClimb,
                climbId: Climb.preview.id,
                heartRate: heartRate
            ),
            measurementSystem: .imperial,
            stepHeight: MeasurementSystem.imperial.defaultStepHeight,
            climb: .preview,
            climbName: Climb.preview.name,
            climbRank: 4,
            climbRankTotal: 1_284
        )
    }

    /// The interval count is frozen into the session's own metadata, exactly as
    /// the routine recorder writes it, so the fixture cannot claim a number the
    /// workout never carried.
    static func routineViewModel(intervalCount: Int? = 8) -> ShareComposerViewModel {
        ShareComposerViewModel(
            workout: recordedWorkout(
                name: "Pyramid 24",
                trackingMode: .routine,
                routineId: UUID().uuidString,
                routineIntervalCount: intervalCount,
                heartRate: true
            ),
            measurementSystem: .imperial,
            stepHeight: MeasurementSystem.imperial.defaultStepHeight
        )
    }

    private static func justClimbViewModel() -> ShareComposerViewModel {
        ShareComposerViewModel(
            workout: recordedWorkout(name: "Just Climb", trackingMode: .justClimb, heartRate: false),
            measurementSystem: .imperial,
            stepHeight: MeasurementSystem.imperial.defaultStepHeight
        )
    }

    /// A sensor-recorded session with a split curve, so the split cluster has
    /// real rows to draw rather than a reconstruction.
    ///
    /// The pace deliberately varies — a hot start, a sag through the middle, a
    /// finishing kick — because a perfectly even climb makes every split bar the
    /// same length and would prove nothing about how the table reads.
    static func recordedWorkout(
        name: String,
        trackingMode: HeadphoneMotionWorkoutTrackingMode,
        climbId: String? = nil,
        routineId: String? = nil,
        routineIntervalCount: Int? = nil,
        heartRate: Bool,
        recordedSteps: Int = 2_046
    ) -> Workout {
        let pace: [Double] = [1.18, 1.08, 0.92, 0.86, 0.94, 1.06, 0.98, 0.9, 1.02, 1.16]
        let buckets = pace.count
        let duration = 1_120
        let interval = duration / buckets
        let total = pace.reduce(0, +)
        var cumulative: [Int] = []
        var running = 0.0
        for (index, weight) in pace.enumerated() {
            running += weight
            cumulative.append(
                index == buckets - 1
                    ? recordedSteps
                    : Int((Double(recordedSteps) * running / total).rounded())
            )
        }

        let metadata = HeadphoneMotionWorkoutMetadata(
            sampleCount: 1_200,
            trackingMode: trackingMode,
            climbId: climbId,
            routineId: routineId,
            routineIntervalCount: routineIntervalCount,
            targetStepCount: recordedSteps,
            climbTargetStepCount: climbId == nil ? nil : recordedSteps,
            stopReason: .targetReached,
            splitCurve: LiveReplaySplitCurve(intervalSeconds: interval, steps: cumulative)
        )
        let startedAt = Date(timeIntervalSince1970: 1_786_000_000)

        return Workout(
            name: name,
            date: startedAt,
            duration: Double(duration),
            steps: recordedSteps,
            floors: Workout.stepsToFloors(recordedSteps, stepsPerFloor: 16),
            avgHeartRate: heartRate ? 148 : nil,
            maxHeartRate: heartRate ? 176 : nil,
            heartRateTimeSeries: heartRate
                ? (0..<buckets).map { index in
                    HeartRateDataPoint(
                        timestamp: startedAt.addingTimeInterval(Double(index * interval)),
                        heartRate: 138 + index * 4
                    )
                }
                : [],
            source: .headphoneMotion,
            sourceMetadata: metadata.jsonString
        )
    }

    private static func solidImage() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 40, height: 87), format: format).image { renderer in
            UIColor.darkGray.setFill()
            renderer.fill(CGRect(x: 0, y: 0, width: 40, height: 87))
        }
    }
}
